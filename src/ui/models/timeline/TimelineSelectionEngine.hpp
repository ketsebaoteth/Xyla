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
 * @brief Resolves timeline selection boundaries, range expansions, and linked
 * clip relationships.
 *
 * Implements marquee box intersection, anchor-to-target shift range resolution,
 * and link graph propagation to guarantee audio-video partner clips select in
 * sync.
 *
 * @note Operates as a stateless query and calculation engine.
 */
class TimelineSelectionEngine {
public:
  /**
   * @brief Compute selected clip identifiers intersecting a marquee bounding
   * box.
   *
   * Queries tracks spanning the track range and identifies clips overlapping
   * the frame interval. Expands matching clips to include their linked partners
   * via the link graph.
   *
   * @param tracks Available timeline tracks to query.
   * @param startFrame Start boundary frame of the marquee rectangle.
   * @param endFrame End boundary frame of the marquee rectangle.
   * @param startTrack First track index covered by marquee.
   * @param endTrack Last track index covered by marquee.
   * @param linkGraph Relationship graph used to expand linked partner clips.
   * @param currentSelection Active selection list prior to marquee evaluation.
   * @param toggle True to invert selection on intersecting clips; false to
   * replace.
   * @return Resolved list of selected clip identifiers.
   */
  [[nodiscard]] static QStringList
  resolveBoxSelection(const std::vector<xyla::TimelineTrack *> &tracks,
                      int64_t startFrame, int64_t endFrame, int startTrack,
                      int endTrack, const xyla::TimelineLinkGraph &linkGraph,
                      const QStringList &currentSelection, bool toggle);

  /**
   * @brief Compute range selection spanning between an anchor clip and a
   * clicked target clip.
   *
   * Selects all clips falling within the bounding frame and track rectangle
   * formed by the two clips.
   *
   * @param tracks Available timeline tracks to query.
   * @param anchorClipId Reference clip identifier initiating the range.
   * @param targetClipId Terminal clip identifier completing the range.
   * @param linkGraph Relationship graph used to expand linked partner clips.
   * @return Bounded list of selected clip identifiers.
   */
  [[nodiscard]] static QStringList
  resolveRangeSelection(const std::vector<xyla::TimelineTrack *> &tracks,
                        const QString &anchorClipId,
                        const QString &targetClipId,
                        const xyla::TimelineLinkGraph &linkGraph);

  /**
   * @brief Compute updated selection after toggling a clip and its linked
   * partners.
   *
   * If all linked clips are already selected, removes them; otherwise adds
   * missing partners.
   *
   * @param currentSelection Active selection list prior to toggle.
   * @param targetClipId Identifier of the clip being clicked.
   * @param linkGraph Relationship graph used to locate partner clips.
   * @return Updated list of selected clip identifiers.
   */
  [[nodiscard]] static QStringList
  resolveToggleSelection(const QStringList &currentSelection,
                         const QString &targetClipId,
                         const xyla::TimelineLinkGraph &linkGraph);

  /**
   * @brief Determine the primary active clip ID from a collection of selected
   * clips.
   *
   * Prioritizes video tracks over audio tracks to establish inspector and
   * properties context.
   *
   * @param tracks Available timeline tracks.
   * @param selectedClipIds Currently selected clip identifiers.
   * @return Primary clip identifier, or empty string if selection is empty.
   */
  [[nodiscard]] static QString
  resolvePrimaryClipId(const std::vector<xyla::TimelineTrack *> &tracks,
                       const QStringList &selectedClipIds);

  /**
   * @brief Verify whether the current selection qualifies to form a new link
   * group.
   *
   * Requires at least two clips that do not already belong to the same link
   * group.
   *
   * @param selectedClipIds Currently selected clip identifiers.
   * @param linkGraph Relationship graph tracking existing links.
   * @return True if clips can be linked together; false otherwise.
   */
  [[nodiscard]] static bool
  canLinkSelection(const QStringList &selectedClipIds,
                   const xyla::TimelineLinkGraph &linkGraph);

  /**
   * @brief Verify whether any currently selected clip belongs to an active link
   * group.
   *
   * @param selectedClipIds Currently selected clip identifiers.
   * @param linkGraph Relationship graph tracking existing links.
   * @return True if at least one selected clip is linked; false otherwise.
   */
  [[nodiscard]] static bool
  canUnlinkSelection(const QStringList &selectedClipIds,
                     const xyla::TimelineLinkGraph &linkGraph);
};

} // namespace xyla::timeline
