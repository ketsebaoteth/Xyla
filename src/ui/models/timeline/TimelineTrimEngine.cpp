#include "TimelineTrimEngine.hpp"
#include "core/timeline/timelineTrack.hpp"

#include <algorithm>
#include <cmath>
#include <limits>

namespace xyla::timeline {

const xyla::TimelineClip *
TimelineTrimEngine::findAdjacentClip(const xyla::TimelineTrack &track,
                                     const QString &clipId, bool searchLeft) {
  const auto *originClip = track.findClip(clipId);
  if (!originClip) {
    return nullptr;
  }

  const int64_t originStart = originClip->getTiming().startFrame;
  const int64_t originEnd =
      originStart + originClip->getTiming().durationFrames;

  const xyla::TimelineClip *bestMatch = nullptr;

  for (const auto &clip : track.getClips()) {
    if (clip.getClipId() == clipId) {
      continue;
    }

    const int64_t candidateStart = clip.getTiming().startFrame;
    const int64_t candidateEnd =
        candidateStart + clip.getTiming().durationFrames;

    if (searchLeft) {
      // predecessor clip ends at or immediately adjacent to our start frame
      if (std::abs(candidateEnd - originStart) <= 1) {
        return &clip;
      }
    } else {
      // successor clip starts at or immediately adjacent to our end frame
      if (std::abs(candidateStart - originEnd) <= 1) {
        return &clip;
      }
    }
  }

  return bestMatch;
}

RollLimits TimelineTrimEngine::calculateRollLimits(
    const xyla::TimelineClip &leftClip, const xyla::TimelineClip &rightClip,
    int64_t leftAssetDuration, int64_t rightAssetDuration) {
  const int64_t leftDuration = leftClip.getTiming().durationFrames;
  const int64_t leftSourceIn = leftClip.getTiming().sourceInFrame;
  const int64_t rightDuration = rightClip.getTiming().durationFrames;
  const int64_t rightSourceIn = rightClip.getTiming().sourceInFrame;

  // left clip cannot shrink past 1 frame and cannot pull media before frame
  // zero
  const int64_t leftMinDurAllowance = std::max<int64_t>(0, leftDuration - 1);
  const int64_t rightHeadAllowance = std::max<int64_t>(0, rightSourceIn);
  const int64_t maxLeftShift =
      std::min(leftMinDurAllowance, rightHeadAllowance);

  // right clip cannot shrink past 1 frame and left clip cannot exceed total
  // source frames
  const int64_t rightMinDurAllowance = std::max<int64_t>(0, rightDuration - 1);
  int64_t leftTailAllowance = std::numeric_limits<int64_t>::max();
  if (leftAssetDuration > 0) {
    leftTailAllowance =
        std::max<int64_t>(0, leftAssetDuration - (leftSourceIn + leftDuration));
  }
  const int64_t maxRightShift =
      std::min(rightMinDurAllowance, leftTailAllowance);

  return {maxLeftShift, maxRightShift};
}

RollResult TimelineTrimEngine::computeRoll(const xyla::TimelineClip &leftClip,
                                           const xyla::TimelineClip &rightClip,
                                           int64_t deltaFrames,
                                           const RollLimits &limits) {
  // clamp delta within safe limits to preserve media boundaries and minimum 1
  // frame length
  const int64_t clampedDelta =
      std::clamp(deltaFrames, -limits.maxLeftFrames, limits.maxRightFrames);

  RollResult result;

  // left clip retains original start while adjusting tail duration
  result.leftStartFrame = leftClip.getTiming().startFrame;
  result.leftDurationFrames =
      leftClip.getTiming().durationFrames + clampedDelta;
  result.leftSourceInFrame = leftClip.getTiming().sourceInFrame;

  // right clip shifts start frame and adjusts head in-point
  result.rightStartFrame = rightClip.getTiming().startFrame + clampedDelta;
  result.rightDurationFrames =
      rightClip.getTiming().durationFrames - clampedDelta;
  result.rightSourceInFrame =
      rightClip.getTiming().sourceInFrame + clampedDelta;

  return result;
}

int64_t TimelineTrimEngine::computeSlip(int64_t originalSourceIn,
                                        int64_t deltaFrames,
                                        int64_t clipDuration,
                                        int64_t totalAssetDuration) {
  const int64_t candidateIn = originalSourceIn - deltaFrames;

  if (totalAssetDuration <= 0) {
    return std::max<int64_t>(0, candidateIn);
  }

  // clamp source in-point between frame zero and maximum allowable tail head
  const int64_t maxSourceIn =
      std::max<int64_t>(0, totalAssetDuration - clipDuration);
  return std::clamp(candidateIn, static_cast<int64_t>(0), maxSourceIn);
}

} // namespace xyla::timeline
