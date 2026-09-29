#pragma once

#include <QString>
#include <QStringList>
#include <cstdint>
#include <vector>

namespace xyla {
class TimelineTrack;
class TimelineClip;
} // namespace xyla

namespace xyla::timeline {

/**
 * @brief Describes a single clip shift operation resulting from a downstream
 * ripple.
 */
struct RippleShiftAction {
  QString clipId;
  int trackIndex{0};
  int64_t originalStartFrame{0};
  int64_t targetStartFrame{0};
};

/**
 * @brief Planning and calculation engine for track and cross-track ripple
 * edits.
 *
 * Computes downstream shift offsets, evaluates live visual ripple projections,
 * and builds atomic shift execution plans for ripple move and trim commands.
 *
 * @note Operates as a stateless calculation engine without mutating track data
 * directly.
 */
class TimelineRippleEngine {
public:
  /**
   * @brief Compute the transient visual ripple frame offset for a given clip.
   *
   * Evaluates whether a clip falls downstream of an active ripple cut frame
   * under global or track-specific ripple modes.
   *
   * @param clipStartFrame Start frame of the clip being evaluated.
   * @param clipTrackIndex Track index of the clip being evaluated.
   * @param leaderClipId Identifier of the clip driving the ripple gesture.
   * @param currentClipId Identifier of the clip being queried.
   * @param cutFrame Boundary frame separating upstream unaffected clips from
   * downstream shifting clips.
   * @param leaderTrack Track index hosting the ripple leader clip.
   * @param deltaFrames Active displacement frame delta from user input.
   * @param globalMode True if ripple shifts all unlocked tracks; false if
   * limited to leader track.
   * @return Frame displacement offset to apply to the queried clip.
   */
  [[nodiscard]] static int64_t calculateProjectedOffset(
      int64_t clipStartFrame, int clipTrackIndex, const QString &leaderClipId,
      const QString &currentClipId, int64_t cutFrame, int leaderTrack,
      int64_t deltaFrames, bool globalMode) noexcept;

  /**
   * @brief Build a list of downstream clip shifts resulting from an insertion
   * or gap close.
   *
   * @param tracks Available timeline tracks to query.
   * @param fromFrame Frame boundary after which clips undergo shifting.
   * @param deltaFrames Signed displacement (positive shifts forward, negative
   * shifts backward).
   * @param targetTrack Track index to shift if globalMode is false.
   * @param globalMode True to shift across all unlocked tracks; false for
   * targetTrack only.
   * @param ignoreClipId Clip identifier excluded from shifts (e.g. the moving
   * clip itself).
   * @return Collection of clip shift actions ready for batch execution.
   */
  [[nodiscard]] static std::vector<RippleShiftAction>
  buildDownstreamShifts(const std::vector<xyla::TimelineTrack *> &tracks,
                        int64_t fromFrame, int64_t deltaFrames, int targetTrack,
                        bool globalMode, const QString &ignoreClipId);

  /**
   * @brief Resolve a collision-free insertion frame on a destination track
   * during ripple placement.
   *
   * Finds nearest gap boundary or aligns to existing clip cuts to prevent
   * accidental split errors.
   *
   * @param track Destination track receiving the dropped clip.
   * @param requestedFrame Frame coordinate requested by cursor drop.
   * @param clipDuration Total duration in frames of the incoming clip.
   * @return Validated insertion frame coordinate.
   */
  [[nodiscard]] static int64_t
  resolveInsertFrame(const xyla::TimelineTrack &track, int64_t requestedFrame,
                     int64_t clipDuration) noexcept;
};

} // namespace xyla::timeline
