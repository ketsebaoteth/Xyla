#include "TimelineCutEngine.hpp"
#include "core/timeline/timelineTrack.hpp"
#include "ui/models/timelineLinkGraph.hpp"

#include <QUuid>
#include <unordered_map>
#include <unordered_set>

namespace xyla::timeline {

CutPlan TimelineCutEngine::planClipCut(
    const std::vector<xyla::TimelineTrack *> &tracks, const QString &clipId,
    const xyla::TimelineLinkGraph &linkGraph, int64_t cutFrame) {
  if (clipId.isEmpty() || tracks.empty() || cutFrame <= 0) {
    return {};
  }

  const xyla::TimelineClip *originClip = nullptr;
  for (const auto *track : tracks) {
    if (!track) {
      continue;
    }
    if (const auto *c = track->findClip(clipId)) {
      originClip = c;
      break;
    }
  }

  if (!originClip) {
    return {};
  }

  // verify frame falls strictly within internal clip boundary
  const int64_t start = originClip->getTiming().startFrame;
  const int64_t end = start + originClip->getTiming().durationFrames;
  if (cutFrame <= start || cutFrame >= end) {
    return {};
  }

  const QStringList linkedIds = linkGraph.getLinkedClipIds(clipId);
  const QString newRightGroupId =
      linkGraph.hasLink(clipId)
          ? QUuid::createUuid().toString(QUuid::WithoutBraces)
          : QString{};

  CutPlan plan;

  for (const auto &id : linkedIds) {
    for (const auto *track : tracks) {
      if (!track || track->getIsLocked()) {
        continue;
      }

      const auto *c = track->findClip(id);
      if (!c) {
        continue;
      }

      const int64_t cStart = c->getTiming().startFrame;
      const int64_t cEnd = cStart + c->getTiming().durationFrames;

      if (cutFrame > cStart && cutFrame < cEnd) {
        const QString rightId =
            QUuid::createUuid().toString(QUuid::WithoutBraces);
        plan.cuts.push_back({id, c->getTiming().trackIndex, cutFrame, rightId,
                             newRightGroupId});
        plan.newSelectionIds.append(rightId);
      }
      break;
    }
  }

  return plan;
}

CutPlan TimelineCutEngine::planRazorCut(
    const std::vector<xyla::TimelineTrack *> &tracks,
    const QStringList &selectedClipIds,
    const xyla::TimelineLinkGraph &linkGraph, int64_t cutFrame,
    int targetTrack) {
  if (tracks.empty() || cutFrame <= 0) {
    return {};
  }

  std::vector<const xyla::TimelineClip *> clipsToCut;
  std::unordered_set<QString> registeredClipIds;

  // case 1: cut intersecting selected clips
  for (const auto &id : selectedClipIds) {
    for (const auto *track : tracks) {
      if (!track || track->getIsLocked()) {
        continue;
      }

      if (const auto *c = track->findClip(id)) {
        const int64_t start = c->getTiming().startFrame;
        const int64_t end = start + c->getTiming().durationFrames;

        if (cutFrame > start && cutFrame < end &&
            !registeredClipIds.count(id)) {
          clipsToCut.push_back(c);
          registeredClipIds.insert(id);
        }
        break;
      }
    }
  }

  // case 2: cut targeted unselected clip if clicked directly
  if (clipsToCut.empty() && targetTrack >= 0 &&
      static_cast<size_t>(targetTrack) < tracks.size()) {
    const auto *track = tracks[static_cast<size_t>(targetTrack)];
    if (track && !track->getIsLocked()) {
      for (const auto &c : track->getClips()) {
        const int64_t start = c.getTiming().startFrame;
        const int64_t end = start + c.getTiming().durationFrames;

        if (cutFrame > start && cutFrame < end) {
          // include targeted clip and its linked partners
          const QStringList linked = linkGraph.getLinkedClipIds(c.getClipId());
          for (const auto &lid : linked) {
            for (const auto *t : tracks) {
              if (!t || t->getIsLocked()) {
                continue;
              }
              if (const auto *partner = t->findClip(lid)) {
                if (!registeredClipIds.count(lid)) {
                  clipsToCut.push_back(partner);
                  registeredClipIds.insert(lid);
                }
                break;
              }
            }
          }
          break;
        }
      }
    }
  }

  // case 3: fallback cut across all unlocked tracks at cut frame
  if (clipsToCut.empty()) {
    for (const auto *track : tracks) {
      if (!track || track->getIsLocked()) {
        continue;
      }

      for (const auto &c : track->getClips()) {
        const int64_t start = c.getTiming().startFrame;
        const int64_t end = start + c.getTiming().durationFrames;

        if (cutFrame > start && cutFrame < end &&
            !registeredClipIds.count(c.getClipId())) {
          clipsToCut.push_back(&c);
          registeredClipIds.insert(c.getClipId());
        }
      }
    }
  }

  if (clipsToCut.empty()) {
    return {};
  }

  // map original link group IDs to newly generated right group IDs
  std::unordered_map<QString, QString> oldToNewGroupMap;
  for (const auto *c : clipsToCut) {
    const QString origGroup = linkGraph.getGroupId(c->getClipId());
    if (!origGroup.isEmpty() && !oldToNewGroupMap.count(origGroup)) {
      oldToNewGroupMap[origGroup] =
          QUuid::createUuid().toString(QUuid::WithoutBraces);
    }
  }

  CutPlan plan;
  plan.cuts.reserve(clipsToCut.size());

  for (const auto *c : clipsToCut) {
    const QString rightId = QUuid::createUuid().toString(QUuid::WithoutBraces);
    const QString origGroup = linkGraph.getGroupId(c->getClipId());
    const QString rightGroupId =
        origGroup.isEmpty() ? QString{} : oldToNewGroupMap[origGroup];

    plan.cuts.push_back({c->getClipId(), c->getTiming().trackIndex, cutFrame,
                         rightId, rightGroupId});
    plan.newSelectionIds.append(rightId);
  }

  return plan;
}

} // namespace xyla::timeline
