#include "TimelineThreePointEngine.hpp"
#include "ui/models/timeline/TimelineEditCommands.hpp"

#include <QUuid>
#include <unordered_set>

namespace xyla::timeline {

ThreePointPlan TimelineThreePointEngine::planInsert(
    const std::vector<xyla::TimelineTrack *> &tracks,
    const std::vector<TargetTrackAssignment> &targets, const QString &assetId,
    const QString &assetName, int64_t sourceIn, int64_t durationFrames,
    int64_t playheadFrame, bool globalRippleMode) {
  if (targets.empty() || tracks.empty() || durationFrames <= 0) {
    return {};
  }

  ThreePointPlan plan;
  if (targets.size() > 1) {
    plan.sharedGroupId = QUuid::createUuid().toString(QUuid::WithoutBraces);
  }

  std::unordered_set<int> tracksToRipple;
  if (globalRippleMode) {
    for (size_t t = 0; t < tracks.size(); ++t) {
      if (tracks[t] && !tracks[t]->getIsLocked()) {
        tracksToRipple.insert(static_cast<int>(t));
      }
    }
  } else {
    for (const auto &tgt : targets) {
      tracksToRipple.insert(tgt.trackIndex);
    }
  }

  for (int tIdx : tracksToRipple) {
    if (tIdx < 0 || static_cast<size_t>(tIdx) >= tracks.size()) {
      continue;
    }

    auto *track = tracks[static_cast<size_t>(tIdx)];
    if (!track || track->getIsLocked()) {
      continue;
    }

    xyla::timeline::ThreePointTrackDelta delta;
    delta.trackIndex = tIdx;

    for (const auto &c : track->getClips()) {
      if (c.getTiming().containsFrame(playheadFrame)) {
        // split clip intersecting playhead: shorten left portion and create new
        // right segment
        const ClipTiming oldTiming = c.getTiming();
        ClipTiming leftTiming = oldTiming;
        leftTiming.durationFrames = playheadFrame - oldTiming.startFrame;

        delta.modifiedClips.push_back(
            {c.getClipId(), tIdx, oldTiming, leftTiming});

        const QString rightClipId =
            QUuid::createUuid().toString(QUuid::WithoutBraces);
        plan.splitOldToNewIds.emplace_back(c.getClipId(), rightClipId);

        TimelineClipCreateInfo rightInfo{
            .clipId = rightClipId,
            .assetId = c.getAssetId(),
            .name = c.getName(),
            .timing = {
                .startFrame = playheadFrame + durationFrames,
                .durationFrames = oldTiming.endFrame() - playheadFrame,
                .sourceInFrame = oldTiming.sourceInFrame +
                                 (playheadFrame - oldTiming.startFrame),
                .trackIndex = tIdx,
                .speed = oldTiming.speed,
            }};
        delta.addedClips.push_back(TimelineClip(rightInfo));
      } else if (c.getTiming().startFrame >= playheadFrame) {
        // shift all subsequent clips forward by inserted duration
        const ClipTiming oldTiming = c.getTiming();
        ClipTiming newTiming = oldTiming;
        newTiming.startFrame += durationFrames;
        delta.modifiedClips.push_back(
            {c.getClipId(), tIdx, oldTiming, newTiming});
      }
    }

    // construct incoming new clip record if this track is an assigned target
    for (const auto &tgt : targets) {
      if (tgt.trackIndex == tIdx) {
        const QString newClipId =
            QUuid::createUuid().toString(QUuid::WithoutBraces);
        if (!plan.sharedGroupId.isEmpty()) {
          plan.newlyPlacedIds.append(newClipId);
        }

        TimelineClipCreateInfo newInfo{.clipId = newClipId,
                                       .assetId = assetId,
                                       .name = assetName,
                                       .timing = {
                                           .startFrame = playheadFrame,
                                           .durationFrames = durationFrames,
                                           .sourceInFrame = sourceIn,
                                           .trackIndex = tIdx,
                                           .speed = 1.0,
                                       }};
        delta.addedClips.push_back(TimelineClip(newInfo));
      }
    }

    plan.deltas.push_back(std::move(delta));
  }

  return plan;
}

ThreePointPlan TimelineThreePointEngine::planOverwrite(
    const std::vector<xyla::TimelineTrack *> &tracks,
    const std::vector<TargetTrackAssignment> &targets, const QString &assetId,
    const QString &assetName, int64_t sourceIn, int64_t durationFrames,
    int64_t playheadFrame) {
  if (targets.empty() || tracks.empty() || durationFrames <= 0) {
    return {};
  }

  ThreePointPlan plan;
  if (targets.size() > 1) {
    plan.sharedGroupId = QUuid::createUuid().toString(QUuid::WithoutBraces);
  }

  const int64_t rangeStart = playheadFrame;
  const int64_t rangeEnd = playheadFrame + durationFrames;

  for (const auto &tgt : targets) {
    if (tgt.trackIndex < 0 ||
        static_cast<size_t>(tgt.trackIndex) >= tracks.size()) {
      continue;
    }

    auto *track = tracks[static_cast<size_t>(tgt.trackIndex)];
    if (!track || track->getIsLocked()) {
      continue;
    }

    xyla::timeline::ThreePointTrackDelta delta;
    delta.trackIndex = tgt.trackIndex;

    for (const auto &c : track->getClips()) {
      if (c.getTiming().endFrame() <= rangeStart ||
          c.getTiming().startFrame >= rangeEnd) {
        continue;
      }

      const ClipTiming oldTiming = c.getTiming();

      if (oldTiming.startFrame < rangeStart &&
          oldTiming.endFrame() > rangeEnd) {
        // clip straddles both boundaries: shorten left half and create new
        // trailing right half
        ClipTiming leftTiming = oldTiming;
        leftTiming.durationFrames = rangeStart - oldTiming.startFrame;
        delta.modifiedClips.push_back(
            {c.getClipId(), tgt.trackIndex, oldTiming, leftTiming});

        const QString rightClipId =
            QUuid::createUuid().toString(QUuid::WithoutBraces);
        plan.splitOldToNewIds.emplace_back(c.getClipId(), rightClipId);

        TimelineClipCreateInfo rightInfo{
            .clipId = rightClipId,
            .assetId = c.getAssetId(),
            .name = c.getName(),
            .timing = {
                .startFrame = rangeEnd,
                .durationFrames = oldTiming.endFrame() - rangeEnd,
                .sourceInFrame =
                    oldTiming.sourceInFrame + (rangeEnd - oldTiming.startFrame),
                .trackIndex = tgt.trackIndex,
                .speed = oldTiming.speed,
            }};
        delta.addedClips.push_back(TimelineClip(rightInfo));
      } else if (oldTiming.startFrame >= rangeStart &&
                 oldTiming.endFrame() <= rangeEnd) {
        // clip completely enclosed within overwrite boundary: delete
        delta.removedClips.push_back(c);
      } else if (oldTiming.startFrame < rangeStart &&
                 oldTiming.endFrame() <= rangeEnd) {
        // clip overlaps head boundary: truncate tail
        ClipTiming newTiming = oldTiming;
        newTiming.durationFrames = rangeStart - oldTiming.startFrame;
        delta.modifiedClips.push_back(
            {c.getClipId(), tgt.trackIndex, oldTiming, newTiming});
      } else if (oldTiming.startFrame >= rangeStart &&
                 oldTiming.endFrame() > rangeEnd) {
        // clip overlaps tail boundary: advance start frame and source in-point
        ClipTiming newTiming = oldTiming;
        const int64_t cutOffset = rangeEnd - oldTiming.startFrame;
        newTiming.startFrame = rangeEnd;
        newTiming.durationFrames = oldTiming.durationFrames - cutOffset;
        newTiming.sourceInFrame = oldTiming.sourceInFrame + cutOffset;
        delta.modifiedClips.push_back(
            {c.getClipId(), tgt.trackIndex, oldTiming, newTiming});
      }
    }

    const QString newClipId =
        QUuid::createUuid().toString(QUuid::WithoutBraces);
    if (!plan.sharedGroupId.isEmpty()) {
      plan.newlyPlacedIds.append(newClipId);
    }

    TimelineClipCreateInfo newInfo{.clipId = newClipId,
                                   .assetId = assetId,
                                   .name = assetName,
                                   .timing = {
                                       .startFrame = rangeStart,
                                       .durationFrames = durationFrames,
                                       .sourceInFrame = sourceIn,
                                       .trackIndex = tgt.trackIndex,
                                       .speed = 1.0,
                                   }};
    delta.addedClips.push_back(TimelineClip(newInfo));

    plan.deltas.push_back(std::move(delta));
  }

  return plan;
}

} // namespace xyla::timeline
