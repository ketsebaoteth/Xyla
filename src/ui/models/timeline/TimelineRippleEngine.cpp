#include "TimelineRippleEngine.hpp"
#include "core/timeline/timelineTrack.hpp"

#include <algorithm>

namespace xyla::timeline {

int64_t TimelineRippleEngine::calculateProjectedOffset(
    int64_t clipStartFrame, int clipTrackIndex, const QString &leaderClipId,
    const QString &currentClipId, int64_t cutFrame, int leaderTrack,
    int64_t deltaFrames, bool globalMode) noexcept {
  // leader clip maintains its own direct drag delta
  if (leaderClipId.isEmpty() || currentClipId == leaderClipId) {
    return 0;
  }

  // only downstream clips positioned at or beyond cut boundary receive offset
  if (clipStartFrame < cutFrame) {
    return 0;
  }

  if (globalMode || clipTrackIndex == leaderTrack) {
    return deltaFrames;
  }

  return 0;
}

std::vector<RippleShiftAction> TimelineRippleEngine::buildDownstreamShifts(
    const std::vector<xyla::TimelineTrack *> &tracks, int64_t fromFrame,
    int64_t deltaFrames, int targetTrack, bool globalMode,
    const QString &ignoreClipId) {
  if (tracks.empty() || deltaFrames == 0) {
    return {};
  }

  std::vector<RippleShiftAction> shifts;

  for (size_t t = 0; t < tracks.size(); ++t) {
    const int trackIndex = static_cast<int>(t);
    const auto *track = tracks[t];

    if (!track || track->getIsLocked()) {
      continue;
    }

    // skip unrelated tracks when running track-constrained ripple
    if (!globalMode && trackIndex != targetTrack) {
      continue;
    }

    for (const auto &clip : track->getClips()) {
      if (!ignoreClipId.isEmpty() && clip.getClipId() == ignoreClipId) {
        continue;
      }

      const int64_t start = clip.getTiming().startFrame;
      if (start >= fromFrame) {
        const int64_t targetStart = std::max<int64_t>(0, start + deltaFrames);
        shifts.push_back({clip.getClipId(), trackIndex, start, targetStart});
      }
    }
  }

  return shifts;
}

int64_t
TimelineRippleEngine::resolveInsertFrame(const xyla::TimelineTrack &track,
                                         int64_t requestedFrame,
                                         int64_t clipDuration) noexcept {
  const int64_t dropFrame = std::max<int64_t>(0, requestedFrame);

  // align insertion to clean boundary if landing directly inside an existing
  // clip
  for (const auto &clip : track.getClips()) {
    const int64_t start = clip.getTiming().startFrame;
    const int64_t end = start + clip.getTiming().durationFrames;

    if (dropFrame >= start && dropFrame < end) {
      // snap to start or end boundary whichever is closer
      const int64_t distStart = dropFrame - start;
      const int64_t distEnd = end - dropFrame;
      return (distStart < distEnd) ? start : end;
    }
  }

  return dropFrame;
}

} // namespace xyla::timeline
