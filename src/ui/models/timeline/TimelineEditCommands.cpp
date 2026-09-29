#include "TimelineEditCommands.hpp"
#include "core/timeline/timelineTrack.hpp"
#include "ui/models/timelineModel.hpp"

namespace xyla::timeline {

// move clips
MoveClipsCommand::MoveClipsCommand(xyla::TimelineModel *model,
                                   std::vector<MoveRecord> moves)
    : xyla::XylaCommand("Move Clips"), m_model(model),
      m_moves(std::move(moves)) {}

void MoveClipsCommand::redo() {
  if (!m_model) {
    return;
  }
  for (const auto &m : m_moves) {
    m_model->applyDirectMove(m.clipId, m.srcTrack, m.dstTrack, m.newStartFrame);
  }
}

void MoveClipsCommand::undo() {
  if (!m_model) {
    return;
  }
  // reverse move direction back to original track and frame
  for (auto it = m_moves.rbegin(); it != m_moves.rend(); ++it) {
    m_model->applyDirectMove(it->clipId, it->dstTrack, it->srcTrack,
                             it->oldStartFrame);
  }
}

QString MoveClipsCommand::text() const {
  return m_moves.size() > 1 ? "Move Clips" : "Move Clip";
}

// add clips
AddClipsCommand::AddClipsCommand(xyla::TimelineModel *model,
                                 std::vector<AddClipPayload> clips,
                                 QString groupId)
    : xyla::XylaCommand("Add Clips"), m_model(model), m_clips(std::move(clips)),
      m_groupId(std::move(groupId)) {}

void AddClipsCommand::redo() {
  if (!m_model) {
    return;
  }

  QStringList addedIds;
  for (const auto &item : m_clips) {
    m_model->applyDirectAdd(item.clip, item.trackIndex);
    addedIds.append(item.clip.getClipId());
  }

  if (addedIds.size() > 1 && !m_groupId.isEmpty()) {
    m_model->applyDirectLink(addedIds, m_groupId);
  }

  m_model->applyDirectSelection(addedIds);
}

void AddClipsCommand::undo() {
  if (!m_model) {
    return;
  }

  for (auto it = m_clips.rbegin(); it != m_clips.rend(); ++it) {
    m_model->applyDirectRemove(it->clip.getClipId(), it->trackIndex);
  }
}

// delete clips
DeleteClipsCommand::DeleteClipsCommand(
    xyla::TimelineModel *model, std::vector<DeletedClipPayload> deletedClips)
    : xyla::XylaCommand("Delete Clips"), m_model(model),
      m_deletedClips(std::move(deletedClips)) {}

void DeleteClipsCommand::redo() {
  if (!m_model) {
    return;
  }
  for (const auto &info : m_deletedClips) {
    m_model->applyDirectRemove(info.clip.getClipId(), info.trackIndex);
  }
}

void DeleteClipsCommand::undo() {
  if (!m_model) {
    return;
  }

  QStringList restoredIds;
  for (const auto &info : m_deletedClips) {
    m_model->applyDirectAdd(info.clip, info.trackIndex);
    restoredIds.append(info.clip.getClipId());
  }

  m_model->applyDirectSelection(restoredIds);
}

QString DeleteClipsCommand::text() const {
  return m_deletedClips.size() > 1 ? "Delete Clips" : "Delete Clip";
}

// batch trim
BatchTrimCommand::BatchTrimCommand(xyla::TimelineModel *model,
                                   std::vector<BatchTrimEntry> entries)
    : xyla::XylaCommand("Trim Clips"), m_model(model),
      m_entries(std::move(entries)) {}

void BatchTrimCommand::redo() {
  if (!m_model) {
    return;
  }
  for (const auto &entry : m_entries) {
    m_model->applyDirectTrim(entry.clipId, entry.trackIndex,
                             entry.newStartFrame, entry.newDurationFrames,
                             entry.newSourceInFrame, entry.isRipple,
                             entry.isGlobal, false);
  }
}

void BatchTrimCommand::undo() {
  if (!m_model) {
    return;
  }
  for (auto it = m_entries.rbegin(); it != m_entries.rend(); ++it) {
    m_model->applyDirectTrim(it->clipId, it->trackIndex, it->oldStartFrame,
                             it->oldDurationFrames, it->oldSourceInFrame,
                             it->isRipple, it->isGlobal, true);
  }
}

// roll edit
RollEditCommand::RollEditCommand(xyla::TimelineModel *model,
                                 RollParticipant left, RollParticipant right)
    : xyla::XylaCommand("Roll Edit"), m_model(model), m_left(std::move(left)),
      m_right(std::move(right)) {}

void RollEditCommand::redo() {
  if (!m_model) {
    return;
  }
  m_model->applyDirectTrim(m_left.clipId, m_left.trackIndex,
                           m_left.newStartFrame, m_left.newDurationFrames,
                           m_left.newSourceInFrame, false, false, false);

  m_model->applyDirectTrim(m_right.clipId, m_right.trackIndex,
                           m_right.newStartFrame, m_right.newDurationFrames,
                           m_right.newSourceInFrame, false, false, false);
}

void RollEditCommand::undo() {
  if (!m_model) {
    return;
  }
  m_model->applyDirectTrim(m_left.clipId, m_left.trackIndex,
                           m_left.oldStartFrame, m_left.oldDurationFrames,
                           m_left.oldSourceInFrame, false, false, true);

  m_model->applyDirectTrim(m_right.clipId, m_right.trackIndex,
                           m_right.oldStartFrame, m_right.oldDurationFrames,
                           m_right.oldSourceInFrame, false, false, true);
}

// batch slip
BatchSlipCommand::BatchSlipCommand(xyla::TimelineModel *model,
                                   std::vector<SlipEntry> entries)
    : xyla::XylaCommand("Slip Clips"), m_model(model),
      m_entries(std::move(entries)) {}

void BatchSlipCommand::redo() {
  if (!m_model) {
    return;
  }
  for (const auto &entry : m_entries) {
    if (auto *track = m_model->getTrack(entry.trackIndex)) {
      if (auto *clip = track->findClip(entry.clipId)) {
        auto timing = clip->getTiming();
        timing.sourceInFrame = entry.newSourceInFrame;
        clip->setTiming(timing);
        m_model->notifyTimelineChanged(entry.trackIndex);
      }
    }
  }
}

void BatchSlipCommand::undo() {
  if (!m_model) {
    return;
  }
  for (const auto &entry : m_entries) {
    if (auto *track = m_model->getTrack(entry.trackIndex)) {
      if (auto *clip = track->findClip(entry.clipId)) {
        auto timing = clip->getTiming();
        timing.sourceInFrame = entry.oldSourceInFrame;
        clip->setTiming(timing);
        m_model->notifyTimelineChanged(entry.trackIndex);
      }
    }
  }
}

// multi cut
MultiCutCommand::MultiCutCommand(xyla::TimelineModel *model,
                                 std::vector<CutInfo> cuts)
    : xyla::XylaCommand("Cut Clips"), m_model(model), m_cuts(std::move(cuts)) {}

void MultiCutCommand::redo() {
  if (!m_model) {
    return;
  }

  QStringList newSelection;
  for (const auto &c : m_cuts) {
    m_model->applyDirectCut(c.id, c.track, c.frame, c.rightId, c.rightGroupId);
    newSelection.append(c.rightId);
  }

  m_model->applyDirectSelection(newSelection);
}

void MultiCutCommand::undo() {
  if (!m_model) {
    return;
  }

  QStringList restoredSelection;
  for (auto it = m_cuts.rbegin(); it != m_cuts.rend(); ++it) {
    m_model->applyDirectUncut(it->id, it->track, it->rightId);
    restoredSelection.append(it->id);
  }

  m_model->applyDirectSelection(restoredSelection);
}

// ripple move
RippleMoveCommand::RippleMoveCommand(xyla::TimelineModel *model, QString clipId,
                                     int srcTrack, int dstTrack,
                                     int64_t dropFrame, bool global)
    : xyla::XylaCommand("Ripple Move"), m_model(model),
      m_clipId(std::move(clipId)), m_srcTrack(srcTrack), m_dstTrack(dstTrack),
      m_dropFrame(dropFrame), m_global(global) {}

void RippleMoveCommand::redo() {
  if (!m_model) {
    return;
  }
  m_model->applyDirectRippleMove(m_clipId, m_srcTrack, m_dstTrack, m_dropFrame,
                                 m_global, m_originalStart, m_splitClipId);
}

void RippleMoveCommand::undo() {
  if (!m_model) {
    return;
  }
  m_model->applyDirectUndoRippleMove(m_clipId, m_srcTrack, m_dstTrack,
                                     m_dropFrame, m_global, m_originalStart,
                                     m_splitClipId);
}

QString RippleMoveCommand::text() const {
  return m_global ? "Global Ripple Move" : "Ripple Move";
}

// select clips
SelectClipsCommand::SelectClipsCommand(xyla::TimelineModel *model,
                                       QStringList oldSelection,
                                       QStringList newSelection)
    : xyla::XylaCommand("Change Selection"), m_model(model),
      m_oldSelection(std::move(oldSelection)),
      m_newSelection(std::move(newSelection)) {}

void SelectClipsCommand::redo() {
  if (m_model) {
    m_model->applyDirectSelection(m_newSelection);
  }
}

void SelectClipsCommand::undo() {
  if (m_model) {
    m_model->applyDirectSelection(m_oldSelection);
  }
}

// lock clip
LockClipCommand::LockClipCommand(xyla::TimelineModel *model, QString clipId,
                                 bool locked)
    : xyla::XylaCommand(locked ? "Lock Clip" : "Unlock Clip"), m_model(model),
      m_clipId(std::move(clipId)), m_locked(locked) {}

void LockClipCommand::redo() {
  if (m_model) {
    m_model->applyDirectClipLock(m_clipId, m_locked);
  }
}

void LockClipCommand::undo() {
  if (m_model) {
    m_model->applyDirectClipLock(m_clipId, !m_locked);
  }
}

QString LockClipCommand::text() const {
  return m_locked ? "Lock Clip" : "Unlock Clip";
}

// lock track
LockTrackCommand::LockTrackCommand(xyla::TimelineModel *model, int trackIndex,
                                   bool locked)
    : xyla::XylaCommand(locked ? "Lock Track" : "Unlock Track"), m_model(model),
      m_trackIndex(trackIndex), m_locked(locked) {}

void LockTrackCommand::redo() {
  if (m_model) {
    m_model->applyDirectTrackLock(m_trackIndex, m_locked);
  }
}

void LockTrackCommand::undo() {
  if (m_model) {
    m_model->applyDirectTrackLock(m_trackIndex, !m_locked);
  }
}

QString LockTrackCommand::text() const {
  return m_locked ? QString("Lock Track %1").arg(m_trackIndex + 1)
                  : QString("Unlock Track %1").arg(m_trackIndex + 1);
}

// link clips
LinkClipsCommand::LinkClipsCommand(
    xyla::TimelineModel *model, QStringList clipIds, QString newGroupId,
    std::vector<std::pair<QString, QString>> previousGroups)
    : xyla::XylaCommand("Link Clips"), m_model(model),
      m_clipIds(std::move(clipIds)), m_newGroupId(std::move(newGroupId)),
      m_previousGroups(std::move(previousGroups)) {}

void LinkClipsCommand::redo() {
  if (m_model) {
    m_model->applyDirectLink(m_clipIds, m_newGroupId);
  }
}

void LinkClipsCommand::undo() {
  if (m_model) {
    m_model->applyDirectRestoreLinkGroups(m_previousGroups);
  }
}

// unlink clips
UnlinkClipsCommand::UnlinkClipsCommand(
    xyla::TimelineModel *model, QStringList clipIds,
    std::vector<std::pair<QString, QString>> previousGroups)
    : xyla::XylaCommand("Unlink Clips"), m_model(model),
      m_clipIds(std::move(clipIds)),
      m_previousGroups(std::move(previousGroups)) {}

void UnlinkClipsCommand::redo() {
  if (m_model) {
    m_model->applyDirectLink(m_clipIds, "");
  }
}

void UnlinkClipsCommand::undo() {
  if (m_model) {
    m_model->applyDirectRestoreLinkGroups(m_previousGroups);
  }
}

// three point edit
ThreePointEditCommand::ThreePointEditCommand(
    xyla::TimelineModel *model, std::vector<ThreePointTrackDelta> deltas,
    QString description)
    : xyla::XylaCommand(description), m_model(model),
      m_deltas(std::move(deltas)), m_description(std::move(description)) {}

void ThreePointEditCommand::redo() {
  if (!m_model) {
    return;
  }

  for (const auto &delta : m_deltas) {
    auto *track = m_model->getTrack(delta.trackIndex);
    if (!track) {
      continue;
    }

    for (const auto &rem : delta.removedClips) {
      track->removeClip(rem.getClipId());
    }

    for (const auto &mod : delta.modifiedClips) {
      if (auto *c = track->findClip(mod.clipId)) {
        c->setTiming(mod.newTiming);
      }
    }

    for (const auto &add : delta.addedClips) {
      track->insertClip(add);
    }

    m_model->notifyTimelineChanged(delta.trackIndex);
  }
}

void ThreePointEditCommand::undo() {
  if (!m_model) {
    return;
  }

  for (auto it = m_deltas.rbegin(); it != m_deltas.rend(); ++it) {
    auto *track = m_model->getTrack(it->trackIndex);
    if (!track) {
      continue;
    }

    for (const auto &add : it->addedClips) {
      track->removeClip(add.getClipId());
    }

    for (const auto &mod : it->modifiedClips) {
      if (auto *c = track->findClip(mod.clipId)) {
        c->setTiming(mod.oldTiming);
      }
    }

    for (const auto &rem : it->removedClips) {
      track->insertClip(rem);
    }

    m_model->notifyTimelineChanged(it->trackIndex);
  }
}

} // namespace xyla::timeline
