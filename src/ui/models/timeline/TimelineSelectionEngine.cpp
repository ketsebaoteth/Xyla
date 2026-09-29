#include "TimelineSelectionEngine.hpp"
#include "core/timeline/timelineTrack.hpp"
#include "ui/models/timelineLinkGraph.hpp"

#include <algorithm>
#include <unordered_set>

namespace xyla::timeline {

QStringList TimelineSelectionEngine::resolveBoxSelection(
    const std::vector<xyla::TimelineTrack *> &tracks, int64_t startFrame,
    int64_t endFrame, int startTrack, int endTrack,
    const xyla::TimelineLinkGraph &linkGraph,
    const QStringList &currentSelection, bool toggle) {
  if (tracks.empty()) {
    return toggle ? currentSelection : QStringList{};
  }

  const int minTrack = std::clamp(std::min(startTrack, endTrack), 0,
                                  static_cast<int>(tracks.size()) - 1);
  const int maxTrack = std::clamp(std::max(startTrack, endTrack), 0,
                                  static_cast<int>(tracks.size()) - 1);

  const int64_t minFrame = std::max<int64_t>(0, std::min(startFrame, endFrame));
  const int64_t maxFrame = std::max(startFrame, endFrame);

  std::unordered_set<QString> intersectingIds;

  // gather clips intersecting marquee bounding coordinates
  for (int t = minTrack; t <= maxTrack; ++t) {
    const auto *track = tracks[static_cast<size_t>(t)];
    if (!track) {
      continue;
    }

    for (const auto &clip : track->getClips()) {
      const int64_t cStart = clip.getTiming().startFrame;
      const int64_t cEnd = cStart + clip.getTiming().durationFrames;

      if (cStart < maxFrame && cEnd > minFrame) {
        // expand clip to include all partners in its link group
        const QStringList linked = linkGraph.getLinkedClipIds(clip.getClipId());
        for (const auto &lid : linked) {
          intersectingIds.insert(lid);
        }
      }
    }
  }

  if (!toggle) {
    QStringList result;
    result.reserve(static_cast<int>(intersectingIds.size()));
    for (const auto &id : intersectingIds) {
      result.append(id);
    }
    return result;
  }

  // toggle membership against existing selection
  QStringList result = currentSelection;
  for (const auto &id : intersectingIds) {
    if (result.contains(id)) {
      result.removeAll(id);
    } else {
      result.append(id);
    }
  }

  return result;
}

QStringList TimelineSelectionEngine::resolveRangeSelection(
    const std::vector<xyla::TimelineTrack *> &tracks,
    const QString &anchorClipId, const QString &targetClipId,
    const xyla::TimelineLinkGraph &linkGraph) {
  const xyla::TimelineClip *anchorClip = nullptr;
  const xyla::TimelineClip *targetClip = nullptr;

  // locate anchor and target clip pointers across tracks
  for (const auto *track : tracks) {
    if (!track) {
      continue;
    }
    if (!anchorClip) {
      anchorClip = track->findClip(anchorClipId);
    }
    if (!targetClip) {
      targetClip = track->findClip(targetClipId);
    }
    if (anchorClip && targetClip) {
      break;
    }
  }

  if (!anchorClip || !targetClip) {
    return linkGraph.getLinkedClipIds(targetClipId);
  }

  const int minTrack = std::min(anchorClip->getTiming().trackIndex,
                                targetClip->getTiming().trackIndex);
  const int maxTrack = std::max(anchorClip->getTiming().trackIndex,
                                targetClip->getTiming().trackIndex);

  const int64_t minFrame = std::min(anchorClip->getTiming().startFrame,
                                    targetClip->getTiming().startFrame);
  const int64_t maxFrame = std::max(anchorClip->getTiming().endFrame(),
                                    targetClip->getTiming().endFrame());

  std::unordered_set<QString> rangeIds;

  for (int t = minTrack; t <= maxTrack; ++t) {
    if (t < 0 || static_cast<size_t>(t) >= tracks.size()) {
      continue;
    }

    const auto *track = tracks[static_cast<size_t>(t)];
    if (!track) {
      continue;
    }

    for (const auto &c : track->getClips()) {
      if (c.getTiming().startFrame < maxFrame &&
          c.getTiming().endFrame() > minFrame) {
        const QStringList linked = linkGraph.getLinkedClipIds(c.getClipId());
        for (const auto &lid : linked) {
          rangeIds.insert(lid);
        }
      }
    }
  }

  QStringList result;
  result.reserve(static_cast<int>(rangeIds.size()));
  for (const auto &id : rangeIds) {
    result.append(id);
  }
  return result;
}

QStringList TimelineSelectionEngine::resolveToggleSelection(
    const QStringList &currentSelection, const QString &targetClipId,
    const xyla::TimelineLinkGraph &linkGraph) {
  const QStringList targetGroup = linkGraph.getLinkedClipIds(targetClipId);

  bool allPresent = true;
  for (const auto &id : targetGroup) {
    if (!currentSelection.contains(id)) {
      allPresent = false;
      break;
    }
  }

  QStringList result = currentSelection;

  // remove entire group if already fully selected, otherwise append missing
  // items
  if (allPresent) {
    for (const auto &id : targetGroup) {
      result.removeAll(id);
    }
  } else {
    for (const auto &id : targetGroup) {
      if (!result.contains(id)) {
        result.append(id);
      }
    }
  }

  return result;
}

QString TimelineSelectionEngine::resolvePrimaryClipId(
    const std::vector<xyla::TimelineTrack *> &tracks,
    const QStringList &selectedClipIds) {
  if (selectedClipIds.isEmpty()) {
    return QString{};
  }

  // prefer video track clip as primary to bind inspector and property controls
  for (const auto &id : selectedClipIds) {
    for (const auto *track : tracks) {
      if (!track || track->getKind() != TrackKind::Video) {
        continue;
      }
      if (track->findClip(id)) {
        return id;
      }
    }
  }

  return selectedClipIds.first();
}

bool TimelineSelectionEngine::canLinkSelection(
    const QStringList &selectedClipIds,
    const xyla::TimelineLinkGraph &linkGraph) {
  if (selectedClipIds.size() < 2) {
    return false;
  }

  QString firstGroupId;
  bool hasFirstGroup = false;
  bool allBelongToSameGroup = true;

  for (const auto &id : selectedClipIds) {
    const QString groupId = linkGraph.getGroupId(id);
    if (groupId.isEmpty()) {
      return true;
    }

    if (!hasFirstGroup) {
      firstGroupId = groupId;
      hasFirstGroup = true;
    } else if (groupId != firstGroupId) {
      allBelongToSameGroup = false;
    }
  }

  return hasFirstGroup && !allBelongToSameGroup;
}

bool TimelineSelectionEngine::canUnlinkSelection(
    const QStringList &selectedClipIds,
    const xyla::TimelineLinkGraph &linkGraph) {
  for (const auto &id : selectedClipIds) {
    if (linkGraph.hasLink(id)) {
      return true;
    }
  }
  return false;
}

} // namespace xyla::timeline
