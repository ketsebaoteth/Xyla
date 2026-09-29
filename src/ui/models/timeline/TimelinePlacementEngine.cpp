#include "TimelinePlacementEngine.hpp"
#include "core/timeline/timelineTrack.hpp"

#include <algorithm>
#include <limits>
#include <unordered_set>

namespace xyla::timeline {

PlacementResult TimelinePlacementEngine::resolvePlacement(
    const std::vector<xyla::TimelineTrack *> &tracks,
    const std::vector<PlacementClip> &movingClips, const QString &anchorClipId,
    int64_t desiredStartFrame, int targetTrackIndex, int64_t originFrame,
    int originTrack, int64_t lastValidFrame, int lastValidTrack) {
  if (movingClips.empty() || tracks.empty()) {
    return {true, desiredStartFrame, targetTrackIndex};
  }

  // single clip path
  if (movingClips.size() == 1) {
    const auto &clip = movingClips.front();

    auto res2D =
        testSinglePlacement(tracks, clip, desiredStartFrame, targetTrackIndex,
                            originFrame, lastValidFrame);
    if (res2D.valid) {
      return res2D;
    }

    // test horizontal movement maintaining last valid track
    auto resX =
        testSinglePlacement(tracks, clip, desiredStartFrame, lastValidTrack,
                            originFrame, lastValidFrame);
    if (resX.valid) {
      return resX;
    }

    // test vertical track swap maintaining last valid frame
    auto resY =
        testSinglePlacement(tracks, clip, lastValidFrame, targetTrackIndex,
                            originFrame, lastValidFrame);
    if (resY.valid) {
      return resY;
    }

    return {false, lastValidFrame, lastValidTrack};
  }

  // multi clip group path
  const int64_t candidateDeltaFrames = desiredStartFrame - originFrame;
  const int candidateDeltaTracks = targetTrackIndex - originTrack;
  const int64_t lastValidDeltaFrames = lastValidFrame - originFrame;
  const int lastValidDeltaTracks = lastValidTrack - originTrack;

  auto gRes2D = testGroupPlacement(tracks, movingClips, candidateDeltaFrames,
                                   candidateDeltaTracks, originFrame,
                                   originTrack, lastValidDeltaFrames);
  if (gRes2D.valid) {
    return gRes2D;
  }

  // test horizontal group delta with locked track offset
  auto gResX = testGroupPlacement(tracks, movingClips, candidateDeltaFrames,
                                  lastValidDeltaTracks, originFrame,
                                  originTrack, lastValidDeltaFrames);
  if (gResX.valid) {
    return gResX;
  }

  // test vertical track shift with locked frame delta
  auto gResY = testGroupPlacement(tracks, movingClips, lastValidDeltaFrames,
                                  candidateDeltaTracks, originFrame,
                                  originTrack, lastValidDeltaFrames);
  if (gResY.valid) {
    return gResY;
  }

  return {false, lastValidFrame, lastValidTrack};
}

bool TimelinePlacementEngine::isTrackCompatible(
    const std::vector<xyla::TimelineTrack *> &tracks, int targetTrackIndex,
    int expectedKind) {
  if (targetTrackIndex < 0 ||
      static_cast<size_t>(targetTrackIndex) >= tracks.size()) {
    return false;
  }

  const auto *track = tracks[static_cast<size_t>(targetTrackIndex)];
  return track && static_cast<int>(track->getKind()) == expectedKind;
}

PlacementResult TimelinePlacementEngine::testSinglePlacement(
    const std::vector<xyla::TimelineTrack *> &tracks, const PlacementClip &clip,
    int64_t desiredFrame, int targetTrackIndex, int64_t originFrame,
    int64_t lastValidFrame) {
  if (!isTrackCompatible(tracks, targetTrackIndex, clip.trackKind)) {
    return {false, lastValidFrame, clip.sourceTrackIndex};
  }

  const int64_t candidateStart = std::max<int64_t>(0, desiredFrame);
  const int64_t candidateEnd = candidateStart + clip.durationFrames;
  const auto *track = tracks[static_cast<size_t>(targetTrackIndex)];

  std::vector<Obstacle> obstacles;
  for (const auto &other : track->getClips()) {
    if (other.getClipId() == clip.clipId) {
      continue;
    }

    const int64_t oStart = other.getTiming().startFrame;
    const int64_t oEnd = oStart + other.getTiming().durationFrames;

    if (candidateStart < oEnd && candidateEnd > oStart) {
      obstacles.push_back({oStart, oEnd});
    }
  }

  if (obstacles.empty()) {
    return {true, candidateStart, targetTrackIndex};
  }

  // snap to nearest obstacle edge depending on drag direction
  int64_t snappedStart = candidateStart;
  if (desiredFrame >= originFrame) {
    int64_t minStart = std::numeric_limits<int64_t>::max();
    for (const auto &obs : obstacles) {
      minStart = std::min(minStart, obs.startFrame);
    }
    snappedStart = minStart - clip.durationFrames;
  } else {
    int64_t maxEnd = std::numeric_limits<int64_t>::min();
    for (const auto &obs : obstacles) {
      maxEnd = std::max(maxEnd, obs.endFrame);
    }
    snappedStart = maxEnd;
  }

  snappedStart = std::max<int64_t>(0, snappedStart);
  const int64_t snappedEnd = snappedStart + clip.durationFrames;

  for (const auto &other : track->getClips()) {
    if (other.getClipId() == clip.clipId) {
      continue;
    }

    const int64_t oStart = other.getTiming().startFrame;
    const int64_t oEnd = oStart + other.getTiming().durationFrames;

    if (snappedStart < oEnd && snappedEnd > oStart) {
      return {false, lastValidFrame, targetTrackIndex};
    }
  }

  return {true, snappedStart, targetTrackIndex};
}

PlacementResult TimelinePlacementEngine::testGroupPlacement(
    const std::vector<xyla::TimelineTrack *> &tracks,
    const std::vector<PlacementClip> &movingClips, int64_t candidateDeltaFrames,
    int candidateDeltaTracks, int64_t originFrame, int originTrack,
    int64_t lastValidDeltaFrames) {
  const size_t numTracks = tracks.size();

  // Determine the track kind of the anchor clip
  int anchorKind = -1;
  for (const auto &mc : movingClips) {
    if (mc.sourceTrackIndex == originTrack) {
      anchorKind = mc.trackKind;
      break;
    }
  }
  if (anchorKind == -1 && !movingClips.empty()) {
    anchorKind = movingClips.front().trackKind;
  }

  // Only apply candidateDeltaTracks to clips sharing the anchor's trackKind
  for (const auto &mc : movingClips) {
    const int effectiveDeltaTracks =
        (mc.trackKind == anchorKind) ? candidateDeltaTracks : 0;
    const int destTrack = mc.sourceTrackIndex + effectiveDeltaTracks;

    if (destTrack < 0 || static_cast<size_t>(destTrack) >= numTracks) {
      return {false, originFrame + lastValidDeltaFrames, originTrack};
    }

    if (!isTrackCompatible(tracks, destTrack, mc.trackKind)) {
      return {false, originFrame + lastValidDeltaFrames, originTrack};
    }
  }

  int64_t minAllowedDelta = std::numeric_limits<int64_t>::min();
  for (const auto &mc : movingClips) {
    minAllowedDelta = std::max(minAllowedDelta, -mc.startFrame);
  }

  const int64_t boundedDelta = std::max(minAllowedDelta, candidateDeltaFrames);

  std::unordered_set<QString> movingIds;
  movingIds.reserve(movingClips.size());
  for (const auto &mc : movingClips) {
    movingIds.insert(mc.clipId);
  }

  struct GroupCollision {
    PlacementClip clip;
    int64_t obstStart{0};
    int64_t obstEnd{0};
  };

  auto queryCollisions = [&](int64_t testDelta) {
    std::vector<GroupCollision> collisions;

    for (const auto &mc : movingClips) {
      const int effectiveDeltaTracks =
          (mc.trackKind == anchorKind) ? candidateDeltaTracks : 0;
      const int destTrack = mc.sourceTrackIndex + effectiveDeltaTracks;
      const int64_t clipStart = mc.startFrame + testDelta;
      const int64_t clipEnd = clipStart + mc.durationFrames;
      const auto *track = tracks[static_cast<size_t>(destTrack)];

      for (const auto &other : track->getClips()) {
        if (movingIds.count(other.getClipId())) {
          continue;
        }

        const int64_t oStart = other.getTiming().startFrame;
        const int64_t oEnd = oStart + other.getTiming().durationFrames;

        if (clipStart < oEnd && clipEnd > oStart) {
          collisions.push_back({mc, oStart, oEnd});
        }
      }
    }
    return collisions;
  };

  auto collisions = queryCollisions(boundedDelta);
  if (collisions.empty()) {
    return {true, originFrame + boundedDelta,
            originTrack + candidateDeltaTracks};
  }

  int64_t resolvedDelta = boundedDelta;
  if (candidateDeltaFrames >= lastValidDeltaFrames) {
    int64_t minSnapRight = std::numeric_limits<int64_t>::max();
    for (const auto &col : collisions) {
      const int64_t snap =
          col.obstStart - col.clip.durationFrames - col.clip.startFrame;
      minSnapRight = std::min(minSnapRight, snap);
    }
    resolvedDelta = std::max(minAllowedDelta, minSnapRight);
  } else {
    int64_t maxSnapLeft = std::numeric_limits<int64_t>::min();
    for (const auto &col : collisions) {
      const int64_t snap = col.obstEnd - col.clip.startFrame;
      maxSnapLeft = std::max(maxSnapLeft, snap);
    }
    resolvedDelta = std::max(minAllowedDelta, maxSnapLeft);
  }

  if (resolvedDelta >= minAllowedDelta &&
      queryCollisions(resolvedDelta).empty()) {
    return {true, originFrame + resolvedDelta,
            originTrack + candidateDeltaTracks};
  }

  return {false, originFrame + lastValidDeltaFrames, originTrack};
}

} // namespace xyla::timeline
