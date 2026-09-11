#include "core/animation/animChannel.hpp"
#include "core/undo/commands/timelineCommands.hpp"
#include "core/undo/xylaUndoStack.hpp"
#include "ui/models/timelineModel.hpp"

namespace xyla {

// @brief Resolves target clip handling a given property descriptor within link
// group context.
TimelineClip *
TimelineModel::resolveClipForProperty(const QString &clipId,
                                      const anim::PropertyDescriptor &desc) {
  auto *clip = findClip(clipId);
  if (!clip)
    return nullptr;

  const bool isAudioProp = (desc.category == anim::PropertyCategory::Audio);

  const int tIdx = clip->trackIndex();
  if (tIdx >= 0 && static_cast<size_t>(tIdx) < m_tracks.size() &&
      m_tracks[tIdx]) {
    const TrackKind k = m_tracks[tIdx]->kind();
    if (isAudioProp && k == TrackKind::Audio)
      return clip;
    if (!isAudioProp && k == TrackKind::Video)
      return clip;
  }

  const QString &groupId = clip->linkGroupId();
  if (!groupId.isEmpty()) {
    for (const auto &track : m_tracks) {
      if (!track)
        continue;
      const TrackKind neededKind =
          isAudioProp ? TrackKind::Audio : TrackKind::Video;
      if (track->kind() != neededKind)
        continue;

      for (const auto &c : track->clips()) {
        if (c.linkGroupId() == groupId) {
          return findClip(c.clipId());
        }
      }
    }
  }

  return nullptr;
}

// @brief Checks if a property has a keyframe at the given timeline frame.
bool TimelineModel::hasKeyframe(const QString &clipId,
                                const QString &propertyId,
                                int64_t frame) const {
  const auto *desc = anim::findPropertyDescriptor(propertyId);
  if (!desc)
    return false;

  auto *clip =
      const_cast<TimelineModel *>(this)->resolveClipForProperty(clipId, *desc);
  if (!clip)
    return false;

  auto *prop = clip->findAnimProperty(propertyId);
  if (!prop)
    return false;

  const int64_t relFrame = frame - clip->startFrame() + clip->sourceInFrame();
  return prop->hasKeyframe(relFrame);
}

// @brief Toggles keyframe presence for property at timeline frame.
void TimelineModel::toggleKeyframe(const QString &clipId,
                                   const QString &propertyId, int64_t frame,
                                   const QVariant &currentValue) {
  const auto *desc = anim::findPropertyDescriptor(propertyId);
  if (!desc)
    return;

  auto *clip = resolveClipForProperty(clipId, *desc);
  if (!clip)
    return;

  auto *prop = clip->findAnimProperty(propertyId);
  if (!prop)
    return;

  const int64_t relFrame = frame - clip->startFrame() + clip->sourceInFrame();

  if (prop->hasKeyframe(relFrame)) {
    prop->removeKeyframe(relFrame);
  } else {
    prop->setKeyframe(relFrame, currentValue.toFloat());
  }

  emit clipPropertiesChanged(clip->clipId());
  emit selectedClipDataChanged();
  markDirty();
  emit visualFrameInvalidated();
}

// @brief Removes a single keyframe for a property at timeline frame.
void TimelineModel::removeKeyframe(const QString &clipId,
                                   const QString &propertyId, int64_t frame) {
  const auto *desc = anim::findPropertyDescriptor(propertyId);
  auto *clip = desc ? resolveClipForProperty(clipId, *desc) : findClip(clipId);
  if (!clip)
    return;

  auto *prop = clip->findAnimProperty(propertyId);
  if (!prop)
    return;

  const int64_t relFrame = frame - clip->startFrame() + clip->sourceInFrame();
  prop->removeKeyframe(relFrame);

  emit clipPropertiesChanged(clip->clipId());
  emit selectedClipDataChanged();
  markDirty();
  emit visualFrameInvalidated();
}

// @brief Moves an existing keyframe to a new timeline frame position.
void TimelineModel::moveKeyframes(const QVariantList &keyframeList,
                                  int64_t deltaFrames) {
  if (keyframeList.isEmpty() || deltaFrames == 0)
    return;

  std::vector<MoveKeyframesCommand::MoveRecord> records;

  for (const auto &item : keyframeList) {
    const QVariantMap map = item.toMap();
    const QString clipId = map.value("clipId").toString();
    const QString propId = map.value("propId").toString();
    const int64_t oldAbs = map.value("frame").toLongLong();
    const int64_t newAbs = std::max<int64_t>(0, oldAbs + deltaFrames);

    if (oldAbs == newAbs)
      continue;

    const auto *desc = anim::findPropertyDescriptor(propId);
    auto *clip =
        desc ? resolveClipForProperty(clipId, *desc) : findClip(clipId);
    if (!clip)
      continue;

    const int64_t clipStart = clip->startFrame();
    const int64_t srcIn = clip->sourceInFrame();

    // If propId is empty (Summary Diamond moved on group/clip row), move all
    // properties at that frame
    if (propId.isEmpty()) {
      for (const auto &d : anim::propertyRegistry()) {
        auto *p = d.accessor ? d.accessor(*clip) : nullptr;
        if (!p || !p->isAnimated())
          continue;

        const int64_t oldRel = oldAbs - clipStart + srcIn;
        const int64_t newRel = newAbs - clipStart + srcIn;

        if (p->hasKeyframe(oldRel)) {
          records.push_back(
              {clip->clipId(), d.id, oldAbs, newAbs, oldRel, newRel});
        }
      }
      continue;
    }

    auto *prop = clip->findAnimProperty(propId);
    if (!prop)
      continue;

    const int64_t oldRel = oldAbs - clipStart + srcIn;
    const int64_t newRel = newAbs - clipStart + srcIn;

    if (prop->hasKeyframe(oldRel)) {
      records.push_back(
          {clip->clipId(), propId, oldAbs, newAbs, oldRel, newRel});
    }
  }

  if (records.empty())
    return;

  if (m_undoStack) {
    m_undoStack->push(
        std::make_unique<MoveKeyframesCommand>(this, std::move(records)));
  } else {
    auto cmd = std::make_unique<MoveKeyframesCommand>(this, std::move(records));
    cmd->redo();
  }
}

void TimelineModel::moveKeyframe(const QString &clipId,
                                 const QString &propertyId, int64_t oldFrame,
                                 int64_t newFrame) {
  if (oldFrame == newFrame)
    return;

  QVariantMap map;
  map["clipId"] = clipId;
  map["propId"] = propertyId;
  map["frame"] = static_cast<qlonglong>(oldFrame);

  moveKeyframes({map}, newFrame - oldFrame);
}

// @brief Returns anim channel info for clip and linked companions with full
// keyframe curve details.
QVariantList TimelineModel::getClipAnimChannels(const QString &clipId,
                                                int64_t currentFrame) const {
  auto *primaryClip = const_cast<TimelineModel *>(this)->findClip(clipId);
  if (!primaryClip)
    return {};

  std::vector<TimelineClip *> contextClips;
  contextClips.push_back(primaryClip);

  if (!primaryClip->linkGroupId().isEmpty()) {
    for (const auto &track : m_tracks) {
      if (!track)
        continue;
      for (const auto &c : track->clips()) {
        if (c.linkGroupId() == primaryClip->linkGroupId() &&
            c.clipId() != primaryClip->clipId()) {
          if (auto *companion =
                  const_cast<TimelineModel *>(this)->findClip(c.clipId())) {
            contextClips.push_back(companion);
          }
        }
      }
    }
  }

  QVariantList result;

  for (auto *clip : contextClips) {
    TrackKind kind = TrackKind::Video;
    if (auto *track = getTrack(static_cast<size_t>(clip->trackIndex())))
      kind = track->kind();

    const int64_t clipStart = clip->startFrame();
    const int64_t srcIn = clip->sourceInFrame();
    const int64_t relFrame = currentFrame - clipStart + srcIn;

    struct Entry {
      const anim::PropertyDescriptor *desc = nullptr;
      anim::AnimProperty *prop = nullptr;
      bool animated = false;
    };
    std::vector<Entry> entries;
    std::unordered_set<QString> animatedParents;

    for (const auto &desc : anim::propertyRegistry()) {
      if (kind == TrackKind::Video &&
          desc.category == anim::PropertyCategory::Audio)
        continue;
      if (kind == TrackKind::Audio &&
          desc.category != anim::PropertyCategory::Audio)
        continue;

      anim::AnimProperty *prop = desc.accessor ? desc.accessor(*clip) : nullptr;
      if (!prop)
        continue;

      const bool animated = prop->isAnimated();
      entries.push_back({&desc, prop, animated});

      if (animated && !desc.parent.isEmpty())
        animatedParents.insert(desc.group + QLatin1Char('|') + desc.parent);
    }

    for (const Entry &e : entries) {
      const bool show =
          e.animated ||
          (!e.desc->parent.isEmpty() &&
           animatedParents.count(e.desc->group + QLatin1Char('|') +
                                 e.desc->parent) > 0);
      if (!show)
        continue;

      anim::AnimChannelInfo info;
      info.clipId = clip->clipId();
      info.id = e.desc->id;
      info.name = e.desc->name;
      info.group = e.desc->group;
      info.parent = e.desc->parent;
      info.color = e.desc->color;
      info.isAnimated = e.animated;

      for (const auto &k : e.prop->keyframes()) {
        const int64_t absFrame = k.frame - srcIn + clipStart;
        info.keyframeFrames.push_back(absFrame);
        if (k.frame == relFrame)
          info.hasKeyframeAtPlayhead = true;

        anim::KeyframeDetail det;
        det.frame = absFrame;
        det.value = k.value;
        det.interpolation = static_cast<int>(k.interpolation);
        det.inX = k.bezier.inX;
        det.inY = k.bezier.inY;
        det.outX = k.bezier.outX;
        det.outY = k.bezier.outY;
        info.details.push_back(det);
      }

      result.append(info.toVariantMap());
    }
  }

  return result;
}

// @brief Evaluates property value for clip at specific timeline frame.
float TimelineModel::getClipEvaluatedProperty(const QString &clipId,
                                              const QString &propertyId,
                                              int64_t frame) const {
  const auto *desc = anim::findPropertyDescriptor(propertyId);
  auto *clip = desc ? const_cast<TimelineModel *>(this)->resolveClipForProperty(
                          clipId, *desc)
                    : const_cast<TimelineModel *>(this)->findClip(clipId);
  if (!clip)
    return 0.0f;

  auto *prop = clip->findAnimProperty(propertyId);
  if (!prop)
    return 0.0f;

  const int64_t relFrame = frame - clip->startFrame() + clip->sourceInFrame();
  return prop->evaluate(relFrame);
}

// @brief Batch removes keyframes via undo command.
void TimelineModel::removeKeyframes(const QVariantList &keyframeList) {
  if (keyframeList.isEmpty())
    return;

  std::vector<DeleteKeyframesCommand::KeyframeRecord> records;

  for (const auto &item : keyframeList) {
    const QVariantMap map = item.toMap();
    const QString clipId = map.value("clipId").toString();
    const QString propId = map.value("propId").toString();
    const int64_t absFrame = map.value("frame").toLongLong();

    const auto *desc = anim::findPropertyDescriptor(propId);
    auto *clip =
        desc ? resolveClipForProperty(clipId, *desc) : findClip(clipId);
    if (!clip) {
      clip = resolveVideoClip(clipId);
    }

    if (!clip) {
      qWarning() << "[removeKeyframes] Clip not found for clipId:" << clipId;
      continue;
    }

    if (propId.isEmpty()) {
      for (const auto &d : anim::propertyRegistry()) {
        auto *p = d.accessor ? d.accessor(*clip) : nullptr;
        if (!p || !p->isAnimated())
          continue;

        const int64_t relFrame =
            absFrame - clip->startFrame() + clip->sourceInFrame();
        if (const auto *kf = p->findKeyframe(relFrame)) {
          DeleteKeyframesCommand::KeyframeRecord rec;
          rec.clipId = clip->clipId();
          rec.propId = d.id;
          rec.absFrame = absFrame;
          rec.relFrame = relFrame;
          rec.value = kf->value;
          rec.interpolation = kf->interpolation;
          rec.bezier = kf->bezier;
          records.push_back(rec);
        }
      }
      continue;
    }

    auto *prop = clip->findAnimProperty(propId);
    if (!prop) {
      qWarning() << "[removeKeyframes] Property not found on clip:" << propId;
      continue;
    }

    const int64_t relFrame =
        absFrame - clip->startFrame() + clip->sourceInFrame();

    if (const auto *kf = prop->findKeyframe(relFrame)) {
      DeleteKeyframesCommand::KeyframeRecord rec;
      rec.clipId = clip->clipId();
      rec.propId = propId;
      rec.absFrame = absFrame;
      rec.relFrame = relFrame;
      rec.value = kf->value;
      rec.interpolation = kf->interpolation;
      rec.bezier = kf->bezier;
      records.push_back(rec);
    } else {
      qWarning() << "[removeKeyframes] findKeyframe returned NULL for relFrame:"
                 << relFrame;
    }
  }

  if (records.empty())
    return;

  if (m_undoStack) {
    m_undoStack->push(
        std::make_unique<DeleteKeyframesCommand>(this, std::move(records)));
  } else {
    auto cmd =
        std::make_unique<DeleteKeyframesCommand>(this, std::move(records));
    cmd->redo();
  }
}

// @brief Updates keyframe position, value, interpolation and handles in
// Value-Time space.
void TimelineModel::updateKeyframe(const QString &clipId,
                                   const QString &propertyId, int64_t oldFrame,
                                   int64_t newFrame, float newValue, int interp,
                                   float inX, float inY, float outX,
                                   float outY) {
  const auto *desc = anim::findPropertyDescriptor(propertyId);
  auto *clip = desc ? resolveClipForProperty(clipId, *desc) : findClip(clipId);
  if (!clip)
    return;

  auto *prop = clip->findAnimProperty(propertyId);
  if (!prop)
    return;

  const int64_t oldRel = oldFrame - clip->startFrame() + clip->sourceInFrame();
  const int64_t newRel = newFrame - clip->startFrame() + clip->sourceInFrame();

  anim::Interpolation it = (interp >= 0)
                               ? static_cast<anim::Interpolation>(interp)
                               : anim::Interpolation::Bezier;

  anim::BezierHandles bz{.outX = outX, .outY = outY, .inX = inX, .inY = inY};

  if (oldRel != newRel) {
    prop->removeKeyframe(oldRel);
  }
  prop->setKeyframe(newRel, newValue, it, bz);

  emit clipPropertiesChanged(clip->clipId());
  emit selectedClipDataChanged();
  markDirty();
  emit visualFrameInvalidated();
}

void TimelineModel::pasteKeyframes(
    const std::vector<anim::ClipboardKeyframe> &keys, int64_t offset,
    anim::MergeMode mode) {
  if (keys.empty())
    return;

  std::vector<PasteKeyframesCommand::KeyRecord> pastedRecords;
  std::vector<PasteKeyframesCommand::KeyRecord> overwrittenRecords;

  for (const auto &k : keys) {
    const auto *desc = anim::findPropertyDescriptor(k.propId);
    auto *clip =
        desc ? resolveClipForProperty(k.clipId, *desc) : findClip(k.clipId);
    if (!clip)
      continue;

    auto *prop = clip->findAnimProperty(k.propId);
    if (!prop)
      continue;

    const int64_t clipStart = clip->startFrame();
    const int64_t srcIn = clip->sourceInFrame();

    const int64_t targetAbsFrame = std::max<int64_t>(0, k.frame + offset);
    const int64_t targetRelFrame = targetAbsFrame - clipStart + srcIn;

    // Handle MergeMode Overwriting
    if (mode == anim::MergeMode::OverwriteAll) {
      for (const auto &existing : prop->keyframes()) {
        overwrittenRecords.push_back({clip->clipId(), k.propId, existing.frame,
                                      existing.value, existing.interpolation,
                                      existing.bezier});
      }
    } else {
      // Mix or OverwriteRange: if a key already exists at target, snapshot it
      // for undo
      if (const auto *existing = prop->findKeyframe(targetRelFrame)) {
        overwrittenRecords.push_back({clip->clipId(), k.propId, targetRelFrame,
                                      existing->value, existing->interpolation,
                                      existing->bezier});
      }
    }

    anim::BezierHandles bezier;
    bezier.inX = k.inX;
    bezier.inY = k.inY;
    bezier.outX = k.outX;
    bezier.outY = k.outY;

    pastedRecords.push_back({clip->clipId(), k.propId, targetRelFrame, k.value,
                             static_cast<anim::Interpolation>(k.interpolation),
                             bezier});
  }

  if (pastedRecords.empty())
    return;

  if (m_undoStack) {
    m_undoStack->push(std::make_unique<PasteKeyframesCommand>(
        this, std::move(pastedRecords), std::move(overwrittenRecords)));
  } else {
    auto cmd = std::make_unique<PasteKeyframesCommand>(
        this, std::move(pastedRecords), std::move(overwrittenRecords));
    cmd->redo();
  }
}
} // namespace xyla
