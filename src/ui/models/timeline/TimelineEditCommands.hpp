#pragma once

#include "core/timeline/timelineClip.hpp"
#include "core/undo/xylaCommand.hpp"

#include <QString>
#include <QStringList>
#include <cstdint>
#include <utility>
#include <vector>

namespace xyla {
class TimelineModel;
}

namespace xyla::timeline {

/**
 * @brief Record describing a spatial move of a single clip from source to
 * destination track.
 */
struct MoveRecord {
  QString clipId;
  int srcTrack{0};
  int dstTrack{0};
  int64_t oldStartFrame{0};
  int64_t newStartFrame{0};
};

/**
 * @brief Atomic undo command translating one or more clips across timeline
 * frames and tracks.
 */
class MoveClipsCommand : public xyla::XylaCommand {
public:
  MoveClipsCommand(xyla::TimelineModel *model, std::vector<MoveRecord> moves);

  void undo() override;
  void redo() override;
  [[nodiscard]] QString text() const override;

private:
  xyla::TimelineModel *m_model{nullptr};
  std::vector<MoveRecord> m_moves;
};

/**
 * @brief Payload descriptor for newly instantiated clips being placed onto a
 * track.
 */
struct AddClipPayload {
  xyla::TimelineClip clip;
  int trackIndex{0};
};

/**
 * @brief Atomic undo command placing new clips onto timeline tracks with
 * optional group linking.
 */
class AddClipsCommand : public xyla::XylaCommand {
public:
  AddClipsCommand(xyla::TimelineModel *model, std::vector<AddClipPayload> clips,
                  QString groupId = QString());

  void undo() override;
  void redo() override;
  [[nodiscard]] QString text() const override { return "Add Clips"; }

private:
  xyla::TimelineModel *m_model{nullptr};
  std::vector<AddClipPayload> m_clips;
  QString m_groupId;
};

/**
 * @brief Payload descriptor capturing removed clip state and origin track
 * index.
 */
struct DeletedClipPayload {
  xyla::TimelineClip clip;
  int trackIndex{0};
};

/**
 * @brief Atomic undo command deleting one or more clips and recording their
 * state for restoration.
 */
class DeleteClipsCommand : public xyla::XylaCommand {
public:
  DeleteClipsCommand(xyla::TimelineModel *model,
                     std::vector<DeletedClipPayload> deletedClips);

  void undo() override;
  void redo() override;
  [[nodiscard]] QString text() const override;

private:
  xyla::TimelineModel *m_model{nullptr};
  std::vector<DeletedClipPayload> m_deletedClips;
};

/**
 * @brief Parameters for an individual clip participating in a synchronized
 * batch trim.
 */
struct BatchTrimEntry {
  QString clipId;
  int trackIndex{0};
  int64_t oldStartFrame{0};
  int64_t oldDurationFrames{0};
  int64_t oldSourceInFrame{0};
  int64_t newStartFrame{0};
  int64_t newDurationFrames{0};
  int64_t newSourceInFrame{0};
  bool isRipple{false};
  bool isGlobal{false};
};

/**
 * @brief Atomic undo command applying synchronized edge trims across multiple
 * linked clips.
 */
class BatchTrimCommand : public xyla::XylaCommand {
public:
  BatchTrimCommand(xyla::TimelineModel *model,
                   std::vector<BatchTrimEntry> entries);

  void undo() override;
  void redo() override;
  [[nodiscard]] QString text() const override { return "Trim Clips"; }

private:
  xyla::TimelineModel *m_model{nullptr};
  std::vector<BatchTrimEntry> m_entries;
};

/**
 * @brief Timing state for one side of an adjacent cut boundary during a roll
 * edit.
 */
struct RollParticipant {
  QString clipId;
  int trackIndex{0};
  int64_t oldStartFrame{0};
  int64_t oldDurationFrames{0};
  int64_t oldSourceInFrame{0};
  int64_t newStartFrame{0};
  int64_t newDurationFrames{0};
  int64_t newSourceInFrame{0};
};

/**
 * @brief Atomic undo command executing a dual-clip roll edit across an adjacent
 * cut boundary.
 */
class RollEditCommand : public xyla::XylaCommand {
public:
  RollEditCommand(xyla::TimelineModel *model, RollParticipant left,
                  RollParticipant right);

  void undo() override;
  void redo() override;
  [[nodiscard]] QString text() const override { return "Roll Edit"; }

private:
  xyla::TimelineModel *m_model{nullptr};
  RollParticipant m_left;
  RollParticipant m_right;
};

/**
 * @brief Describes the source in-point modification for a slipping clip.
 */
struct SlipEntry {
  QString clipId;
  int trackIndex{0};
  int64_t oldSourceInFrame{0};
  int64_t newSourceInFrame{0};
};

/**
 * @brief Atomic undo command applying in-point offsets across one or more
 * slipping clips.
 */
class BatchSlipCommand : public xyla::XylaCommand {
public:
  BatchSlipCommand(xyla::TimelineModel *model, std::vector<SlipEntry> entries);

  void undo() override;
  void redo() override;
  [[nodiscard]] QString text() const override { return "Slip Clips"; }

private:
  xyla::TimelineModel *m_model{nullptr};
  std::vector<SlipEntry> m_entries;
};

/**
 * @brief Atomic split instruction for an individual clip.
 */
struct CutInfo {
  QString id;
  int track{0};
  int64_t frame{0};
  QString rightId;
  QString rightGroupId;
};

/**
 * @brief Atomic undo command slicing one or more clips at specified frame
 * coordinates.
 */
class MultiCutCommand : public xyla::XylaCommand {
public:
  MultiCutCommand(xyla::TimelineModel *model, std::vector<CutInfo> cuts);

  void undo() override;
  void redo() override;
  [[nodiscard]] QString text() const override { return "Cut Clips"; }

private:
  xyla::TimelineModel *m_model{nullptr};
  std::vector<CutInfo> m_cuts;
};

/**
 * @brief Atomic undo command executing a ripple translation and shifting
 * downstream clips.
 */
class RippleMoveCommand : public xyla::XylaCommand {
public:
  RippleMoveCommand(xyla::TimelineModel *model, QString clipId, int srcTrack,
                    int dstTrack, int64_t dropFrame, bool global);

  void undo() override;
  void redo() override;
  [[nodiscard]] QString text() const override;

private:
  xyla::TimelineModel *m_model{nullptr};
  QString m_clipId;
  int m_srcTrack{0};
  int m_dstTrack{0};
  int64_t m_dropFrame{0};
  bool m_global{false};
  int64_t m_originalStart{0};
  QString m_splitClipId;
};

/**
 * @brief Atomic undo command modifying the active selection set.
 */
class SelectClipsCommand : public xyla::XylaCommand {
public:
  SelectClipsCommand(xyla::TimelineModel *model, QStringList oldSelection,
                     QStringList newSelection);

  void undo() override;
  void redo() override;
  [[nodiscard]] QString text() const override { return "Change Selection"; }

private:
  xyla::TimelineModel *m_model{nullptr};
  QStringList m_oldSelection;
  QStringList m_newSelection;
};

/**
 * @brief Atomic undo command modifying lock state on a specific clip.
 */
class LockClipCommand : public xyla::XylaCommand {
public:
  LockClipCommand(xyla::TimelineModel *model, QString clipId, bool locked);

  void undo() override;
  void redo() override;
  [[nodiscard]] QString text() const override;

private:
  xyla::TimelineModel *m_model{nullptr};
  QString m_clipId;
  bool m_locked{false};
};

/**
 * @brief Atomic undo command modifying lock state on an entire track lane.
 */
class LockTrackCommand : public xyla::XylaCommand {
public:
  LockTrackCommand(xyla::TimelineModel *model, int trackIndex, bool locked);

  void undo() override;
  void redo() override;
  [[nodiscard]] QString text() const override;

private:
  xyla::TimelineModel *m_model{nullptr};
  int m_trackIndex{0};
  bool m_locked{false};
};

/**
 * @brief Atomic undo command creating a synchronization link across multiple
 * clips.
 */
class LinkClipsCommand : public xyla::XylaCommand {
public:
  LinkClipsCommand(xyla::TimelineModel *model, QStringList clipIds,
                   QString newGroupId,
                   std::vector<std::pair<QString, QString>> previousGroups);

  void undo() override;
  void redo() override;
  [[nodiscard]] QString text() const override { return "Link Clips"; }

private:
  xyla::TimelineModel *m_model{nullptr};
  QStringList m_clipIds;
  QString m_newGroupId;
  std::vector<std::pair<QString, QString>> m_previousGroups;
};

/**
 * @brief Atomic undo command breaking synchronization links between clips.
 */
class UnlinkClipsCommand : public xyla::XylaCommand {
public:
  UnlinkClipsCommand(xyla::TimelineModel *model, QStringList clipIds,
                     std::vector<std::pair<QString, QString>> previousGroups);

  void undo() override;
  void redo() override;
  [[nodiscard]] QString text() const override { return "Unlink Clips"; }

private:
  xyla::TimelineModel *m_model{nullptr};
  QStringList m_clipIds;
  std::vector<std::pair<QString, QString>> m_previousGroups;
};

/**
 * @brief Track modification record for delta-based 3-point insert and overwrite
 * edits.
 */
struct ThreePointModifiedTiming {
  QString clipId;
  int trackIndex{0};
  xyla::ClipTiming oldTiming;
  xyla::ClipTiming newTiming;
};

/**
 * @brief Collection of additions, deletions, and adjustments executed on a
 * single track.
 */
struct ThreePointTrackDelta {
  int trackIndex{0};
  std::vector<xyla::TimelineClip> addedClips;
  std::vector<xyla::TimelineClip> removedClips;
  std::vector<ThreePointModifiedTiming> modifiedClips;
};

/**
 * @brief Atomic undo command applying multi-track modifications resulting from
 * 3-point edits.
 */
class ThreePointEditCommand : public xyla::XylaCommand {
public:
  ThreePointEditCommand(xyla::TimelineModel *model,
                        std::vector<ThreePointTrackDelta> deltas,
                        QString description = "3-Point Edit");

  void undo() override;
  void redo() override;
  [[nodiscard]] QString text() const override { return m_description; }

private:
  xyla::TimelineModel *m_model{nullptr};
  std::vector<ThreePointTrackDelta> m_deltas;
  QString m_description;
};

} // namespace xyla::timeline
