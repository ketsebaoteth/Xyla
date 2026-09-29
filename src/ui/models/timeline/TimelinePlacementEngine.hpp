#pragma once

#include <QString>
#include <QStringList>
#include <cstdint>
#include <vector>

namespace xyla {
class TimelineTrack;
}

namespace xyla::timeline {

/**
 * @brief Describes the spatial bounds and origin of a clip participating in
 * drag-placement.
 */
struct PlacementClip {
  QString clipId;
  int sourceTrackIndex{0};
  int64_t startFrame{0};
  int64_t durationFrames{0};
  int trackKind{0};
};

/**
 * @brief Represents the resolved spatial coordinates resulting from a placement
 * test.
 */
struct PlacementResult {
  bool valid{false};
  int64_t frame{0};
  int trackIndex{0};
};

/**
 * @brief Resolves collision-free timeline placements for single and group drag
 * operations.
 *
 * Validates target track compatibility, detects collisions with existing track
 * clips, computes boundary snap adjustments, and falls back across decoupled
 * spatial axes.
 *
 * @note Operates as a stateless calculation engine without mutating timeline
 * model state.
 */
class TimelinePlacementEngine {
public:
  /**
   * @brief Resolve collision-free placement for moving clips relative to an
   * anchor clip.
   *
   * Tests candidate placement in both axes, attempts single-axis recovery if
   * collisions occur, and falls back to last-known valid coordinates when
   * blocked.
   *
   * @param tracks Available timeline tracks used for collision checks.
   * @param movingClips All clips participating in the active drag gesture.
   * @param anchorClipId Identifier of the primary clip driving the drag
   * gesture.
   * @param desiredStartFrame Target start frame requested for the anchor clip.
   * @param targetTrackIndex Target track index requested for the anchor clip.
   * @param originFrame Start frame of the anchor clip when the drag gesture
   * initiated.
   * @param originTrack Track index of the anchor clip when the drag gesture
   * initiated.
   * @param lastValidFrame Most recent collision-free frame coordinate.
   * @param lastValidTrack Most recent collision-free track index.
   * @return Resolved coordinates and validity flag.
   */
  [[nodiscard]] static PlacementResult
  resolvePlacement(const std::vector<xyla::TimelineTrack *> &tracks,
                   const std::vector<PlacementClip> &movingClips,
                   const QString &anchorClipId, int64_t desiredStartFrame,
                   int targetTrackIndex, int64_t originFrame, int originTrack,
                   int64_t lastValidFrame, int lastValidTrack);

private:
  struct Obstacle {
    int64_t startFrame{0};
    int64_t endFrame{0};
  };

  static bool
  isTrackCompatible(const std::vector<xyla::TimelineTrack *> &tracks,
                    int targetTrackIndex, int expectedKind);

  static PlacementResult
  testSinglePlacement(const std::vector<xyla::TimelineTrack *> &tracks,
                      const PlacementClip &clip, int64_t desiredFrame,
                      int targetTrackIndex, int64_t originFrame,
                      int64_t lastValidFrame);

  static PlacementResult
  testGroupPlacement(const std::vector<xyla::TimelineTrack *> &tracks,
                     const std::vector<PlacementClip> &movingClips,
                     int64_t candidateDeltaFrames, int candidateDeltaTracks,
                     int64_t originFrame, int originTrack,
                     int64_t lastValidDeltaFrames);
};

} // namespace xyla::timeline
