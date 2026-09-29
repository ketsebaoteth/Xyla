#pragma once

#include <QString>
#include <cstdint>

namespace xyla {
class TimelineTrack;
class TimelineClip;
} // namespace xyla

namespace xyla::timeline {

/**
 * @brief Boundary frame allowances constraining a two-sided roll edit between
 * adjacent clips.
 */
struct RollLimits {
  int64_t maxLeftFrames{0};
  int64_t maxRightFrames{0};
};

/**
 * @brief Timing state resulting from a calculated roll edit applied to adjacent
 * clips.
 */
struct RollResult {
  int64_t leftStartFrame{0};
  int64_t leftDurationFrames{0};
  int64_t leftSourceInFrame{0};
  int64_t rightStartFrame{0};
  int64_t rightDurationFrames{0};
  int64_t rightSourceInFrame{0};
};

/**
 * @brief Mathematical and spatial engine for roll, slip, and edge-trim edit
 * operations.
 *
 * Computes allowable frame bounds, clamping limits, and neighbor adjacency
 * without modifying timeline tracks or clip data.
 *
 * @note Operates as a pure stateless calculation helper.
 */
class TimelineTrimEngine {
public:
  /**
   * @brief Find the immediate spatial neighbor clip on the same track.
   *
   * Identifies adjacent clips whose start or end frame touches the reference
   * clip within a single-frame boundary tolerance.
   *
   * @param track Timeline track hosting the target clips.
   * @param clipId Identifier of the reference clip.
   * @param searchLeft True to find the predecessor clip to the left; false for
   * successor to the right.
   * @return Pointer to adjacent clip if found and touching; nullptr otherwise.
   */
  [[nodiscard]] static const xyla::TimelineClip *
  findAdjacentClip(const xyla::TimelineTrack &track, const QString &clipId,
                   bool searchLeft);

  /**
   * @brief Calculate maximum bidirectional frame shift allowances for a roll
   * edit.
   *
   * Computes limits based on available source media tails and minimum duration
   * constraints.
   *
   * @param leftClip Predecessor clip located to the left of the cut point.
   * @param rightClip Successor clip located to the right of the cut point.
   * @param leftAssetDuration Total available source media frames for the left
   * clip.
   * @param rightAssetDuration Total available source media frames for the right
   * clip.
   * @return Frame limits restricting leftward and rightward cut point
   * movements.
   */
  [[nodiscard]] static RollLimits
  calculateRollLimits(const xyla::TimelineClip &leftClip,
                      const xyla::TimelineClip &rightClip,
                      int64_t leftAssetDuration, int64_t rightAssetDuration);

  /**
   * @brief Apply a delta frame adjustment to a roll boundary and compute
   * resulting timings.
   *
   * Clamps delta to allowed limits and adjusts left/right durations and source
   * in-points symmetrically.
   *
   * @param leftClip Predecessor clip being adjusted.
   * @param rightClip Successor clip being adjusted.
   * @param deltaFrames Requested frame shift (negative shifts cut left,
   * positive shifts cut right).
   * @param limits Allowable frame shift boundaries.
   * @return Computed timing parameters for both clips.
   */
  [[nodiscard]] static RollResult
  computeRoll(const xyla::TimelineClip &leftClip,
              const xyla::TimelineClip &rightClip, int64_t deltaFrames,
              const RollLimits &limits);

  /**
   * @brief Calculate a clamped source in-point frame during a slip edit
   * gesture.
   *
   * Shifts media offset while locking timeline duration and timeline start
   * frame.
   *
   * @param originalSourceIn Frame offset when the slip gesture initiated.
   * @param deltaFrames Interactive frame delta requested by user input.
   * @param clipDuration Timeline duration in frames of the slipping clip.
   * @param totalAssetDuration Total frames available in the underlying media
   * asset.
   * @return Validated source in-point clamped to source boundary limits.
   * @note Returns zero if clip has infinite or non-media duration.
   */
  [[nodiscard]] static int64_t computeSlip(int64_t originalSourceIn,
                                           int64_t deltaFrames,
                                           int64_t clipDuration,
                                           int64_t totalAssetDuration);
};

} // namespace xyla::timeline
