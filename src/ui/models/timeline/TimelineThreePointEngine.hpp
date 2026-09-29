#pragma once

#include "core/timeline/timelineTrack.hpp"
#include "ui/models/timeline/TimelineEditCommands.hpp"

#include <QString>
#include <QStringList>
#include <cstdint>
#include <utility>
#include <vector>

namespace xyla::timeline {

/**
 * @brief Complete calculation plan for a 3-point timeline insert or overwrite
 * edit.
 */
struct ThreePointPlan {
  std::vector<xyla::timeline::ThreePointTrackDelta> deltas;
  std::vector<std::pair<QString, QString>> splitOldToNewIds;
  QStringList newlyPlacedIds;
  QString sharedGroupId;

  [[nodiscard]] bool isValid() const noexcept { return !deltas.empty(); }
};

/**
 * @brief Target placement track descriptor paired with media track kind.
 */
struct TargetTrackAssignment {
  int trackIndex{0};
  bool isAudio{false};
};

/**
 * @brief Planning and interval-splicing engine for 3-point insert and overwrite
 * edits.
 *
 * Calculates clip straddle splits, head/tail truncation, ripple shifts, and
 * newly placed clip records without mutating track collections or persistent
 * model state.
 *
 * @note Produces execution plans consumable by ThreePointEditCommand.
 */
class TimelineThreePointEngine {
public:
  /**
   * @brief Compute track modifications for an insert edit at the playhead
   * position.
   *
   * Splits overlapping clips at the cut frame, ripples downstream clips
   * forward, and constructs newly placed clip segments spanning the target
   * duration.
   *
   * @param tracks Available timeline tracks to query.
   * @param targets Target tracks assigned to receive incoming media.
   * @param assetId Media asset identifier being placed.
   * @param assetName Display name assigned to new clips.
   * @param sourceIn In-point frame within the source asset.
   * @param durationFrames Number of frames to insert.
   * @param playheadFrame Timeline insertion frame coordinate.
   * @param globalRippleMode True to ripple all unlocked tracks; false for
   * target tracks only.
   * @return Execution plan with all track deltas and link split mappings.
   */
  [[nodiscard]] static ThreePointPlan
  planInsert(const std::vector<xyla::TimelineTrack *> &tracks,
             const std::vector<TargetTrackAssignment> &targets,
             const QString &assetId, const QString &assetName, int64_t sourceIn,
             int64_t durationFrames, int64_t playheadFrame,
             bool globalRippleMode);

  /**
   * @brief Compute track modifications for an overwrite edit over a designated
   * frame interval.
   *
   * Slices, trims, or removes existing clips overlapping the target range,
   * and constructs replacement clip records without shifting downstream media.
   *
   * @param tracks Available timeline tracks to query.
   * @param targets Target tracks assigned to receive incoming media.
   * @param assetId Media asset identifier being placed.
   * @param assetName Display name assigned to new clips.
   * @param sourceIn In-point frame within the source asset.
   * @param durationFrames Number of frames to overwrite.
   * @param playheadFrame Timeline start frame coordinate where overwrite
   * begins.
   * @return Execution plan with all track deltas and link split mappings.
   */
  [[nodiscard]] static ThreePointPlan
  planOverwrite(const std::vector<xyla::TimelineTrack *> &tracks,
                const std::vector<TargetTrackAssignment> &targets,
                const QString &assetId, const QString &assetName,
                int64_t sourceIn, int64_t durationFrames,
                int64_t playheadFrame);
};

} // namespace xyla::timeline
