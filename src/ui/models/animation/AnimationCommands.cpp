#include "AnimationCommands.hpp"
#include "core/animation/animProperty.hpp"
#include "core/timeline/timelineTrack.hpp"
#include "ui/models/timelineModel.hpp"

namespace xyla::anim {

DeleteKeyframesCommand::DeleteKeyframesCommand(
    xyla::TimelineModel *model, std::vector<KeyframeRecord> records)
    : xyla::XylaCommand("Delete Keyframes"), m_model(model),
      m_records(std::move(records)) {}

void DeleteKeyframesCommand::redo() {
  if (!m_model) {
    return;
  }
  // remove keyframes directly from each matching property
  for (const auto &rec : m_records) {
    if (auto *clip = m_model->findClip(rec.clipId)) {
      if (auto *prop = clip->findPropertyByPath(rec.propId)) {
        prop->removeKeyframe(rec.relFrame);
      }
    }
  }
  m_model->markDirty();
}

void DeleteKeyframesCommand::undo() {
  if (!m_model) {
    return;
  }
  // restore keyframe value, interpolation, and bezier tangents
  for (const auto &rec : m_records) {
    if (auto *clip = m_model->findClip(rec.clipId)) {
      if (auto *prop = clip->findPropertyByPath(rec.propId)) {
        prop->setKeyframe(rec.relFrame, rec.value, rec.interpolation,
                          rec.bezier);
      }
    }
  }
  m_model->markDirty();
}

QString DeleteKeyframesCommand::text() const {
  return m_records.size() > 1 ? "Delete Keyframes" : "Delete Keyframe";
}

MoveKeyframesCommand::MoveKeyframesCommand(xyla::TimelineModel *model,
                                           std::vector<MoveRecord> moves)
    : xyla::XylaCommand("Move Keyframes"), m_model(model),
      m_moves(std::move(moves)) {}

void MoveKeyframesCommand::redo() {
  if (!m_model) {
    return;
  }
  // advance keyframes to new relative frame positions
  for (const auto &mv : m_moves) {
    if (auto *clip = m_model->findClip(mv.clipId)) {
      if (auto *prop = clip->findPropertyByPath(mv.propId)) {
        prop->moveKeyframe(mv.oldRelFrame, mv.newRelFrame);
      }
    }
  }
  m_model->markDirty();
}

void MoveKeyframesCommand::undo() {
  if (!m_model) {
    return;
  }
  // revert keyframe positions back to original frames
  for (auto it = m_moves.rbegin(); it != m_moves.rend(); ++it) {
    if (auto *clip = m_model->findClip(it->clipId)) {
      if (auto *prop = clip->findPropertyByPath(it->propId)) {
        prop->moveKeyframe(it->newRelFrame, it->oldRelFrame);
      }
    }
  }
  m_model->markDirty();
}

QString MoveKeyframesCommand::text() const {
  return m_moves.size() > 1 ? "Move Keyframes" : "Move Keyframe";
}

PasteKeyframesCommand::PasteKeyframesCommand(
    xyla::TimelineModel *model, std::vector<KeyRecord> pastedKeys,
    std::vector<KeyRecord> overwrittenKeys)
    : xyla::XylaCommand("Paste Keyframes"), m_model(model),
      m_pastedKeys(std::move(pastedKeys)),
      m_overwrittenKeys(std::move(overwrittenKeys)) {}

void PasteKeyframesCommand::redo() {
  if (!m_model) {
    return;
  }
  // apply pasted keyframe records onto target properties
  for (const auto &k : m_pastedKeys) {
    if (auto *clip = m_model->findClip(k.clipId)) {
      if (auto *prop = clip->findPropertyByPath(k.propId)) {
        prop->setKeyframe(k.relFrame, k.value, k.interpolation, k.bezier);
      }
    }
  }
  m_model->markDirty();
}

void PasteKeyframesCommand::undo() {
  if (!m_model) {
    return;
  }
  // remove pasted keyframes
  for (const auto &k : m_pastedKeys) {
    if (auto *clip = m_model->findClip(k.clipId)) {
      if (auto *prop = clip->findPropertyByPath(k.propId)) {
        prop->removeKeyframe(k.relFrame);
      }
    }
  }
  // restore overwritten keyframe collisions
  for (const auto &k : m_overwrittenKeys) {
    if (auto *clip = m_model->findClip(k.clipId)) {
      if (auto *prop = clip->findPropertyByPath(k.propId)) {
        prop->setKeyframe(k.relFrame, k.value, k.interpolation, k.bezier);
      }
    }
  }
  m_model->markDirty();
}

UpdateKeyframeCommand::UpdateKeyframeCommand(xyla::TimelineModel *model,
                                             std::vector<Record> records,
                                             QString description)
    : xyla::XylaCommand(description), m_model(model),
      m_records(std::move(records)), m_description(std::move(description)) {}

void UpdateKeyframeCommand::applyState(const Record &rec,
                                       const KeyframeState &from,
                                       const KeyframeState &to) {
  if (!m_model) {
    return;
  }

  auto *clip = m_model->findClip(rec.clipId);
  if (!clip) {
    return;
  }

  auto *prop = clip->findPropertyByPath(rec.propId);
  if (!prop) {
    return;
  }

  // if frame moved, remove old frame position first
  if (from.relFrame != to.relFrame) {
    prop->removeKeyframe(from.relFrame);
  }

  prop->setKeyframe(to.relFrame, to.value, to.interpolation, to.bezier);
}

void UpdateKeyframeCommand::redo() {
  for (const auto &rec : m_records) {
    applyState(rec, rec.oldState, rec.newState);
  }
  if (m_model) {
    m_model->markDirty();
  }
}

void UpdateKeyframeCommand::undo() {
  for (const auto &rec : m_records) {
    applyState(rec, rec.newState, rec.oldState);
  }
  if (m_model) {
    m_model->markDirty();
  }
}

} // namespace xyla::anim
