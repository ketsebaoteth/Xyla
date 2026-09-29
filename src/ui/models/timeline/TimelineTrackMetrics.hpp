#pragma once

#include <cstddef>
#include <vector>

namespace xyla::timeline {

/**
 * @brief Manages track vertical layout metrics and coordinate conversions.
 *
 * Tracks individual row heights, computes cumulative vertical offsets,
 * and resolves canvas coordinates to track indices.
 *
 * @note Maintains internal prefix sums updated on height changes or track count
 * adjustments.
 */
class TimelineTrackMetrics {
public:
  /**
   * @brief Construct track metrics with an initial default height.
   *
   * @param defaultHeight Default height in pixels assigned to unconfigured
   * tracks.
   */
  explicit TimelineTrackMetrics(int defaultHeight = 68);

  /**
   * @brief Synchronize the tracked row count with the timeline model.
   *
   * Resizes internal metrics buffers, preserving existing custom heights
   * and assigning default height to newly appended rows.
   *
   * @param count Total number of tracks in the timeline.
   */
  void setTrackCount(size_t count);

  /**
   * @brief Assign a custom display height to a specific track.
   *
   * Updates cumulative offsets and total height if the height changes.
   *
   * @param trackIndex Zero-based track index.
   * @param height New track height in pixels.
   * @return True if the height changed and metrics were recalculated; false
   * otherwise.
   * @note Rejects negative or zero heights and out-of-range track indices.
   */
  bool setTrackHeight(int trackIndex, int height);

  /**
   * @brief Retrieve the pixel height of a specific track.
   *
   * @param trackIndex Zero-based track index.
   * @return Track height in pixels, or default height if out of range.
   */
  [[nodiscard]] int trackHeight(int trackIndex) const noexcept;

  /**
   * @brief Retrieve the vertical pixel offset from the top of the canvas to the
   * track top edge.
   *
   * @param trackIndex Zero-based track index.
   * @return Top Y coordinate in pixels.
   * @note Returns calculated offset for valid indices, or extrapolated position
   * if out of range.
   */
  [[nodiscard]] int trackY(int trackIndex) const noexcept;

  /**
   * @brief Find the track index located at a given canvas vertical coordinate.
   *
   * @param canvasY Vertical pixel coordinate relative to the content top edge.
   * @return Matching zero-based track index, clamped to available track bounds.
   */
  [[nodiscard]] int trackAtY(int canvasY) const noexcept;

  [[nodiscard]] int totalHeight() const noexcept { return m_totalHeight; }
  [[nodiscard]] size_t trackCount() const noexcept { return m_heights.size(); }

private:
  void recalculateOffsets();

  int m_defaultHeight{68};
  std::vector<int> m_heights;
  std::vector<int> m_offsets;
  int m_totalHeight{0};
};

} // namespace xyla::timeline
