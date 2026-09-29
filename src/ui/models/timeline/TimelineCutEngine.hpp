#pragma once

#include <QString>
#include <QStringList>
#include <cstdint>
#include <vector>

namespace xyla {
class TimelineTrack;
class TimelineLinkGraph;
} // namespace xyla

namespace xyla::timeline {

/**
 * @brief Describes a single atomic split operation on a clip segment.
 */
struct CutDescriptor {
  QString sourceClipId;
  int trackIndex{0};
  int64_t cutFrame{0};
  QString newRightClipId;
  QString newRightGroupId;
};

/**
 * @brief Complete execution plan containing all cuts and selection state for a
 * razor operation.
 */
struct CutPlan {
  std::vector<CutDescriptor> cuts;
  QStringList newSelectionIds;

  [[nodiscard]] bool isEmpty() const noexcept { return cuts.empty(); }
};

/**
 * @brief Planning and resolution engine for single-clip, multi-clip, and razor
 * cuts.
 *
 * Resolves split boundaries, generates identifiers for successor segments,
 * and forks link groups so severed partner clips remain synchronized.
 *
 * @note Operates as a stateless calculation helper producing execution plans
 * for undo commands.
 */
class TimelineCutEngine {
public:
  /**
   * @brief Compute an atomic cut plan for a specific clip and its linked
   * partners.
   *
   * Validates that the split point falls strictly within the clip boundary,
   * forks existing link groups, and generates new IDs for the right segments.
   *
   * @param tracks Available timeline tracks to query.
   * @param clipId Identifier of the clip being cut.
   * @param linkGraph Relationship graph used to expand linked partner clips.
   * @param cutFrame Timeline frame coordinate where the cut occurs.
   * @return Execution plan with all required cut operations.
   */
  [[nodiscard]] static CutPlan
  planClipCut(const std::vector<xyla::TimelineTrack *> &tracks,
              const QString &clipId, const xyla::TimelineLinkGraph &linkGraph,
              int64_t cutFrame);

  /**
   * @brief Compute an atomic razor cut plan based on active selection and
   * cursor coordinates.
   *
   * Evaluates selection context: cuts selected clips if intersecting, cuts the
   * clicked track clip if specified, or executes a global split across all
   * unlocked tracks intersecting the frame.
   *
   * @param tracks Available timeline tracks to query.
   * @param selectedClipIds Currently selected clip identifiers.
   * @param linkGraph Relationship graph used to maintain link group
   * synchronization.
   * @param cutFrame Timeline frame coordinate where the cut occurs.
   * @param targetTrack Zero-based track index directly targeted, or -1 for
   * global evaluation.
   * @return Execution plan with all required cut operations and post-cut
   * selection targets.
   */
  [[nodiscard]] static CutPlan
  planRazorCut(const std::vector<xyla::TimelineTrack *> &tracks,
               const QStringList &selectedClipIds,
               const xyla::TimelineLinkGraph &linkGraph, int64_t cutFrame,
               int targetTrack = -1);
};

} // namespace xyla::timeline
