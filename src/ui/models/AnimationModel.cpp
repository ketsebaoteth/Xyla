#include "AnimationModel.hpp"
#include "core/undo/xylaUndoStack.hpp"
#include "timelineModel.hpp"
#include "ui/models/animation/AnimationCommands.hpp"

#include <algorithm>
#include <cmath>
#include <unordered_set>
#include <vector>

namespace xyla {

std::vector<TimelineClip *>
AnimationModel::resolveClipsForProperty(const QString &clipId,
                                        const QString &propertyId) {
  std::vector<TimelineClip *> matches;
  if (!m_timelineModel) {
    return matches;
  }

  auto *clip = m_timelineModel->findClip(clipId);
  if (!clip) {
    return matches;
  }

  if (clip->findPropertyByPath(propertyId) != nullptr) {
    matches.push_back(clip);
  }

  // gather companion clips across linked audio and video tracks
  const QStringList linkedClipIds = m_timelineModel->getLinkedClipIds(clipId);
  for (const auto &id : linkedClipIds) {
    if (id == clipId) {
      continue;
    }
    if (auto *candidateClip = m_timelineModel->findClip(id)) {
      if (candidateClip->findPropertyByPath(propertyId) != nullptr) {
        matches.push_back(candidateClip);
      }
    }
  }

  return matches;
}

std::vector<const TimelineClip *> AnimationModel::resolveClipsForProperty(
    const QString &clipId, const QString &propertyId) const noexcept {
  std::vector<const TimelineClip *> matches;
  if (!m_timelineModel) {
    return matches;
  }

  const auto *clip = m_timelineModel->findClip(clipId);
  if (!clip) {
    return matches;
  }

  if (clip->findPropertyByPath(propertyId) != nullptr) {
    matches.push_back(clip);
  }

  const QStringList linkedClipIds = m_timelineModel->getLinkedClipIds(clipId);
  for (const auto &id : linkedClipIds) {
    if (id == clipId) {
      continue;
    }
    if (const auto *candidateClip = m_timelineModel->findClip(id)) {
      if (candidateClip->findPropertyByPath(propertyId) != nullptr) {
        matches.push_back(candidateClip);
      }
    }
  }

  return matches;
}

void AnimationModel::toggleKeyframe(const QString &clipId,
                                    const QString &propertyId, int64_t frame,
                                    const QVariant &currentValue) {
  if (clipId.isEmpty() || propertyId.isEmpty() || !m_timelineModel) {
    return;
  }

  auto *clip = m_timelineModel->findClip(clipId);
  if (!clip) {
    return;
  }

  const int64_t targetFrame =
      m_playbackManager ? m_playbackManager->currentFrame() : frame;
  if (!clip->getTiming().containsFrame(targetFrame)) {
    return;
  }

  const FrameIndex localFrame =
      clip->getTiming().timelineToLocalFrame(targetFrame);
  auto table = m_timelineModel->animationTable();
  if (!table) {
    return;
  }

  // resolve standard property path prefix for slot handle lookup
  QString address;
  if (propertyId.startsWith(clipId)) {
    address = propertyId;
  } else if (propertyId.startsWith(QLatin1String("text.")) ||
             propertyId.startsWith(QLatin1String("transform.")) ||
             propertyId.startsWith(QLatin1String("audio.")) ||
             propertyId.startsWith(QLatin1String("svg."))) {
    address = clipId + QLatin1Char('.') + propertyId;
  } else {
    address = clipId + QStringLiteral(".transform.") + propertyId;
  }

  auto handle = table->findHandle(address);
  if (!handle.isValid()) {
    return;
  }

  auto *slot = table->getSlot(handle);
  if (!slot || !slot->isAnimatableFloat) {
    return;
  }

  float val = 0.0f;
  if (currentValue.isValid() && !currentValue.isNull()) {
    val = currentValue.toFloat();
  } else {
    val = slot->animProp.evaluate(localFrame);
  }

  // toggle keyframe existence at current playhead frame
  if (slot->animProp.hasKeyframe(localFrame)) {
    slot->animProp.removeKeyframe(localFrame);
  } else {
    slot->animProp.setKeyframe(localFrame, val);
  }

  emit keyframesChanged(clip->getClipId());
  emit channelsInvalidated();
  emit m_timelineModel->clipPropertiesChanged(clip->getClipId());
  emit m_timelineModel->selectedClipDataChanged();
  m_timelineModel->markDirty();
  emit m_timelineModel->visualFrameInvalidated();
}

void AnimationModel::removeKeyframe(const QString &clipId,
                                    const QString &propertyId, int64_t frame) {
  if (clipId.isEmpty() || propertyId.isEmpty() || !m_timelineModel) {
    return;
  }

  auto clips = resolveClipsForProperty(clipId, propertyId);
  if (clips.empty()) {
    return;
  }

  for (auto *clip : clips) {
    if (!clip || !clip->getTiming().containsFrame(frame)) {
      continue;
    }

    auto *prop = clip->findPropertyByPath(propertyId);
    if (!prop) {
      continue;
    }

    const FrameIndex localFrame = clip->getTiming().timelineToLocalFrame(frame);
    if (prop->hasKeyframe(localFrame)) {
      prop->removeKeyframe(localFrame);
      emit m_timelineModel->clipPropertiesChanged(clip->getClipId());
    }
  }

  emit m_timelineModel->selectedClipDataChanged();
  m_timelineModel->markDirty();
  emit m_timelineModel->visualFrameInvalidated();
}

void AnimationModel::moveKeyframes(const QVariantList &keyframeList,
                                   int64_t deltaFrames) {
  if (keyframeList.isEmpty() || deltaFrames == 0 || !m_timelineModel) {
    return;
  }

  std::vector<anim::MoveKeyframesCommand::MoveRecord> records;

  for (const auto &item : keyframeList) {
    const QVariantMap map = item.toMap();
    const QString clipId = map.value("clipId").toString();
    const QString propId = map.value("propId").toString();
    const int64_t oldAbs = map.value("frame").toLongLong();
    const int64_t newAbs = std::max<int64_t>(0, oldAbs + deltaFrames);

    if (oldAbs == newAbs || clipId.isEmpty()) {
      continue;
    }

    // move all property channels if no property path is specified
    if (propId.isEmpty()) {
      auto *clip = m_timelineModel->findClip(clipId);
      if (!clip) {
        continue;
      }

      const int64_t oldRel = clip->getTiming().timelineToLocalFrame(oldAbs);
      const int64_t newRel =
          std::max<int64_t>(0, clip->getTiming().timelineToLocalFrame(newAbs));

      for (const auto &comp : clip->getComponents()) {
        if (!comp) {
          continue;
        }

        std::vector<anim::AnimChannelInfo> channels;
        comp->collectChannelInfo(
            clip->getClipId(), clip->getTiming().startFrame, oldRel, channels);

        for (const auto &ch : channels) {
          if (auto *p = clip->findPropertyByPath(ch.id)) {
            if (p->hasKeyframe(oldRel)) {
              records.push_back(
                  {clip->getClipId(), ch.id, oldAbs, newAbs, oldRel, newRel});
            }
          }
        }
      }
      continue;
    }

    auto targetClips = resolveClipsForProperty(clipId, propId);
    if (targetClips.empty()) {
      continue;
    }

    for (auto *clip : targetClips) {
      if (!clip) {
        continue;
      }

      auto *prop = clip->findPropertyByPath(propId);
      if (!prop) {
        continue;
      }

      const int64_t oldRel = clip->getTiming().timelineToLocalFrame(oldAbs);
      const int64_t newRel =
          std::max<int64_t>(0, clip->getTiming().timelineToLocalFrame(newAbs));

      if (prop->hasKeyframe(oldRel)) {
        records.push_back(
            {clip->getClipId(), propId, oldAbs, newAbs, oldRel, newRel});
      }
    }
  }

  if (records.empty()) {
    return;
  }

  if (m_undoStack) {
    m_undoStack->push(std::make_unique<anim::MoveKeyframesCommand>(
        m_timelineModel, std::move(records)));
  } else {
    auto cmd = std::make_unique<anim::MoveKeyframesCommand>(m_timelineModel,
                                                            std::move(records));
    cmd->redo();
  }
}

void AnimationModel::moveKeyframe(const QString &clipId,
                                  const QString &propertyId, int64_t oldFrame,
                                  int64_t newFrame) {
  if (oldFrame == newFrame) {
    return;
  }

  QVariantMap map;
  map["clipId"] = clipId;
  map["propId"] = propertyId;
  map["frame"] = static_cast<qlonglong>(oldFrame);

  moveKeyframes({map}, newFrame - oldFrame);
}

QVariantList AnimationModel::getClipAnimChannels(const QString &clipId,
                                                 int64_t currentFrame) const {
  if (!m_timelineModel || clipId.isEmpty()) {
    return {};
  }

  auto table = m_timelineModel->animationTable();
  if (!table) {
    return {};
  }

  const auto *primaryClip = m_timelineModel->findClip(clipId);
  if (!primaryClip) {
    return {};
  }

  std::vector<const TimelineClip *> contextClips;
  contextClips.push_back(primaryClip);

  const QStringList linkedIds = m_timelineModel->getLinkedClipIds(clipId);
  for (const auto &id : linkedIds) {
    if (id != clipId) {
      if (const auto *companion = m_timelineModel->findClip(id)) {
        contextClips.push_back(companion);
      }
    }
  }

  std::vector<anim::AnimChannelInfo> rawChannels;

  auto resolveColor = [](const QString &propId) -> QString {
    if (propId.endsWith("posX") || propId.endsWith("X"))
      return "#EF4444";
    if (propId.endsWith("posY") || propId.endsWith("Y"))
      return "#22C55E";
    if (propId.contains("scale"))
      return "#3B82F6";
    if (propId.contains("rotation"))
      return "#EAB308";
    if (propId.contains("opacity"))
      return "#A855F7";
    if (propId.contains("volume"))
      return "#06B6D4";
    if (propId.contains("pan"))
      return "#F97316";
    return "#3B82F6";
  };

  auto resolveParent = [](const QString &propId) -> QString {
    if (propId.contains("pos") || propId.contains("Position"))
      return "Position";
    if (propId.contains("scale") || propId.contains("Scale"))
      return "Scale";
    return "";
  };

  for (const auto *clip : contextClips) {
    if (!clip) {
      continue;
    }

    const QString cId = clip->getClipId();
    const int64_t clipStart = clip->getTiming().startFrame;
    const int64_t relFrame =
        clip->getTiming().timelineToLocalFrame(currentFrame);

    for (const auto &slot : table->allSlots()) {
      if (!slot.inUse || slot.scopeId != cId || !slot.isAnimatableFloat) {
        continue;
      }

      if (slot.animProp.getKeyframeCount() == 0 &&
          !slot.animProp.getIsAnimated()) {
        continue;
      }

      anim::AnimChannelInfo info;
      info.scopeId = cId;
      info.id = slot.address.startsWith(cId + ".")
                    ? slot.address.mid(cId.length() + 1)
                    : slot.address;
      info.name = slot.name;
      info.group =
          slot.group.isEmpty() ? QStringLiteral("Parameters") : slot.group;
      info.parent = resolveParent(info.id);
      info.color = resolveColor(info.id);
      info.isAnimated = true;

      for (const auto &k : slot.animProp.getKeyframes()) {
        const int64_t absF = k.frame + clipStart;
        info.keyframeFrames.push_back(absF);
        if (k.frame == relFrame) {
          info.hasKeyframeAtPlayhead = true;
        }

        anim::KeyframeDetail det;
        det.frame = absF;
        det.value = k.value;
        det.interpolation = static_cast<int>(k.interpolation);
        det.inX = k.bezier.inX;
        det.inY = k.bezier.inY;
        det.outX = k.bezier.outX;
        det.outY = k.bezier.outY;
        info.details.push_back(det);
      }

      rawChannels.push_back(std::move(info));
    }
  }

  QVariantList result;
  result.reserve(static_cast<qsizetype>(rawChannels.size()));
  for (const auto &ch : rawChannels) {
    result.append(ch.toVariantMap());
  }

  return result;
}

float AnimationModel::getClipEvaluatedProperty(const QString &clipId,
                                               const QString &propertyId,
                                               int64_t frame) const {
  if (clipId.isEmpty() || propertyId.isEmpty() || !m_timelineModel) {
    return 0.0f;
  }

  const auto *clip = m_timelineModel->findClip(clipId);
  if (!clip) {
    return 0.0f;
  }

  const FrameIndex localFrame = clip->getTiming().timelineToLocalFrame(frame);
  auto table = m_timelineModel->animationTable();
  if (!table) {
    return 0.0f;
  }

  QString address;
  if (propertyId.startsWith(clipId)) {
    address = propertyId;
  } else if (propertyId.startsWith(QLatin1String("text.")) ||
             propertyId.startsWith(QLatin1String("transform.")) ||
             propertyId.startsWith(QLatin1String("audio.")) ||
             propertyId.startsWith(QLatin1String("svg."))) {
    address = clipId + QLatin1Char('.') + propertyId;
  } else {
    address = clipId + QStringLiteral(".transform.") + propertyId;
  }

  auto handle = table->findHandle(address);
  if (handle.isValid()) {
    return table->evaluateFloat(handle, localFrame);
  }

  return 0.0f;
}

bool AnimationModel::hasKeyframe(const QString &clipId,
                                 const QString &propertyId,
                                 int64_t frame) const {
  if (clipId.isEmpty() || propertyId.isEmpty() || !m_timelineModel) {
    return false;
  }

  const auto *clip = m_timelineModel->findClip(clipId);
  if (!clip || !clip->getTiming().containsFrame(frame)) {
    return false;
  }

  const FrameIndex localFrame = clip->getTiming().timelineToLocalFrame(frame);
  auto table = m_timelineModel->animationTable();
  if (!table) {
    return false;
  }

  QString address;
  if (propertyId.startsWith(clipId)) {
    address = propertyId;
  } else if (propertyId.startsWith(QLatin1String("text.")) ||
             propertyId.startsWith(QLatin1String("transform.")) ||
             propertyId.startsWith(QLatin1String("audio.")) ||
             propertyId.startsWith(QLatin1String("svg."))) {
    address = clipId + QLatin1Char('.') + propertyId;
  } else {
    address = clipId + QStringLiteral(".transform.") + propertyId;
  }

  auto handle = table->findHandle(address);
  if (handle.isValid()) {
    if (const auto *slot = table->getSlot(handle)) {
      return slot->animProp.hasKeyframe(localFrame);
    }
  }

  return false;
}

void AnimationModel::removeKeyframes(const QVariantList &keyframeList) {
  if (keyframeList.isEmpty() || !m_timelineModel) {
    return;
  }

  std::vector<anim::DeleteKeyframesCommand::KeyframeRecord> records;

  for (const auto &item : keyframeList) {
    const QVariantMap map = item.toMap();
    const QString clipId = map.value("clipId").toString();
    const QString propId = map.value("propId").toString();
    const int64_t absFrame = map.value("frame").toLongLong();

    if (clipId.isEmpty()) {
      continue;
    }

    if (propId.isEmpty()) {
      auto *clip = m_timelineModel->findClip(clipId);
      if (!clip || !clip->getTiming().containsFrame(absFrame)) {
        continue;
      }

      const FrameIndex relFrame =
          clip->getTiming().timelineToLocalFrame(absFrame);

      for (const auto &comp : clip->getComponents()) {
        if (!comp) {
          continue;
        }

        std::vector<anim::AnimChannelInfo> channels;
        comp->collectChannelInfo(clip->getClipId(),
                                 clip->getTiming().startFrame, relFrame,
                                 channels);

        for (const auto &ch : channels) {
          if (auto *p = clip->findPropertyByPath(ch.id)) {
            if (const auto *kf = p->findKeyframe(relFrame)) {
              records.push_back({clip->getClipId(), ch.id, absFrame, relFrame,
                                 kf->value, kf->interpolation, kf->bezier});
            }
          }
        }
      }
      continue;
    }

    auto targetClips = resolveClipsForProperty(clipId, propId);
    if (targetClips.empty()) {
      continue;
    }

    for (auto *clip : targetClips) {
      if (!clip || !clip->getTiming().containsFrame(absFrame)) {
        continue;
      }

      auto *prop = clip->findPropertyByPath(propId);
      if (!prop) {
        continue;
      }

      const FrameIndex relFrame =
          clip->getTiming().timelineToLocalFrame(absFrame);
      if (const auto *kf = prop->findKeyframe(relFrame)) {
        records.push_back({clip->getClipId(), propId, absFrame, relFrame,
                           kf->value, kf->interpolation, kf->bezier});
      }
    }
  }

  if (records.empty()) {
    return;
  }

  if (m_undoStack) {
    m_undoStack->push(std::make_unique<anim::DeleteKeyframesCommand>(
        m_timelineModel, std::move(records)));
  } else {
    auto cmd = std::make_unique<anim::DeleteKeyframesCommand>(
        m_timelineModel, std::move(records));
    cmd->redo();
  }
}

void AnimationModel::updateKeyframe(const QString &clipId,
                                    const QString &propertyId, int64_t oldFrame,
                                    int64_t newFrame, float newValue,
                                    int interp, float inX, float inY,
                                    float outX, float outY) {
  if (clipId.isEmpty() || propertyId.isEmpty() || !m_timelineModel) {
    return;
  }

  auto targetClips = resolveClipsForProperty(clipId, propertyId);
  if (targetClips.empty()) {
    return;
  }

  std::vector<anim::UpdateKeyframeCommand::Record> records;
  bool stateChanged = false;

  auto floatEquals = [](float a, float b) noexcept {
    return std::abs(a - b) < 1e-4f;
  };

  for (auto *clip : targetClips) {
    if (!clip || !clip->getTiming().containsFrame(oldFrame)) {
      continue;
    }

    const FrameIndex oldRel = clip->getTiming().timelineToLocalFrame(oldFrame);
    const FrameIndex newRel = std::max<FrameIndex>(
        0, clip->getTiming().timelineToLocalFrame(newFrame));

    auto *prop = clip->findPropertyByPath(propertyId);
    if (!prop && (propertyId == "scale" || propertyId == "transform.scale")) {
      prop = clip->findPropertyByPath("transform.scaleX");
    }
    if (!prop) {
      continue;
    }

    const auto *existingKf = prop->findKeyframe(oldRel);
    if (!existingKf) {
      continue;
    }

    anim::UpdateKeyframeCommand::KeyframeState oldState{
        oldRel, existingKf->value, existingKf->interpolation,
        existingKf->bezier};

    anim::Interpolation it = (interp >= 0)
                                 ? static_cast<anim::Interpolation>(interp)
                                 : existingKf->interpolation;
    anim::BezierHandles bz{.outX = outX, .outY = outY, .inX = inX, .inY = inY};

    anim::UpdateKeyframeCommand::KeyframeState newState{newRel, newValue, it,
                                                        bz};

    const bool isIdentical =
        (oldState.relFrame == newState.relFrame &&
         floatEquals(oldState.value, newState.value) &&
         oldState.interpolation == newState.interpolation &&
         floatEquals(oldState.bezier.inX, newState.bezier.inX) &&
         floatEquals(oldState.bezier.inY, newState.bezier.inY) &&
         floatEquals(oldState.bezier.outX, newState.bezier.outX) &&
         floatEquals(oldState.bezier.outY, newState.bezier.outY));

    if (isIdentical) {
      continue;
    }

    stateChanged = true;

    const bool isScaleLocked =
        (propertyId == "scale" || propertyId == "transform.scale") ||
        (clip->getIsUniformScale() &&
         (propertyId == "scaleX" || propertyId == "scaleY" ||
          propertyId == "transform.scaleX" ||
          propertyId == "transform.scaleY"));

    if (isScaleLocked) {
      records.push_back(
          {clip->getClipId(), "transform.scaleX", oldState, newState});
      records.push_back(
          {clip->getClipId(), "transform.scaleY", oldState, newState});
    } else {
      records.push_back({clip->getClipId(), propertyId, oldState, newState});
    }
  }

  if (!stateChanged || records.empty()) {
    return;
  }

  const bool isBezierOnly =
      (oldFrame == newFrame &&
       floatEquals(records[0].oldState.value, records[0].newState.value));
  const QString descText =
      isBezierOnly ? "Adjust Bezier Handles" : "Edit Keyframe";

  if (m_undoStack) {
    m_undoStack->push(std::make_unique<anim::UpdateKeyframeCommand>(
        m_timelineModel, std::move(records), descText));
  } else {
    auto cmd = std::make_unique<anim::UpdateKeyframeCommand>(
        m_timelineModel, std::move(records), descText);
    cmd->redo();
  }
}

void AnimationModel::pasteKeyframes(
    const std::vector<anim::ClipboardKeyframe> &keys, int64_t offset,
    anim::MergeMode mode) {
  if (keys.empty() || !m_timelineModel) {
    return;
  }

  std::vector<anim::PasteKeyframesCommand::KeyRecord> pastedRecords;
  std::vector<anim::PasteKeyframesCommand::KeyRecord> overwrittenRecords;
  std::unordered_set<QString> clearedProperties;

  for (const auto &k : keys) {
    if (k.clipId.isEmpty() || k.propId.isEmpty()) {
      continue;
    }

    auto targetClips = resolveClipsForProperty(k.clipId, k.propId);
    if (targetClips.empty()) {
      if (auto *directClip = m_timelineModel->findClip(k.clipId)) {
        targetClips.push_back(directClip);
      }
    }

    for (auto *clip : targetClips) {
      if (!clip) {
        continue;
      }

      auto *prop = clip->findPropertyByPath(k.propId);
      if (!prop) {
        continue;
      }

      const int64_t targetAbsFrame = std::max<int64_t>(0, k.frame + offset);
      const FrameIndex targetRelFrame = std::max<FrameIndex>(
          0, clip->getTiming().timelineToLocalFrame(targetAbsFrame));
      const QString propKey = clip->getClipId() + "." + k.propId;

      if (mode == anim::MergeMode::OverwriteAll) {
        if (clearedProperties.find(propKey) == clearedProperties.end()) {
          clearedProperties.insert(propKey);
          for (const auto &existing : prop->getKeyframes()) {
            overwrittenRecords.push_back(
                {clip->getClipId(), k.propId, existing.frame, existing.value,
                 existing.interpolation, existing.bezier});
          }
        }
      } else {
        if (const auto *existing = prop->findKeyframe(targetRelFrame)) {
          overwrittenRecords.push_back(
              {clip->getClipId(), k.propId, targetRelFrame, existing->value,
               existing->interpolation, existing->bezier});
        }
      }

      anim::BezierHandles bezier{
          .outX = k.outX, .outY = k.outY, .inX = k.inX, .inY = k.inY};

      pastedRecords.push_back(
          {clip->getClipId(), k.propId, targetRelFrame, k.value,
           static_cast<anim::Interpolation>(k.interpolation), bezier});
    }
  }

  if (pastedRecords.empty()) {
    return;
  }

  if (m_undoStack) {
    m_undoStack->push(std::make_unique<anim::PasteKeyframesCommand>(
        m_timelineModel, std::move(pastedRecords),
        std::move(overwrittenRecords)));
  } else {
    auto cmd = std::make_unique<anim::PasteKeyframesCommand>(
        m_timelineModel, std::move(pastedRecords),
        std::move(overwrittenRecords));
    cmd->redo();
  }
}

} // namespace xyla
