#include "TimelineTrackMetrics.hpp"

#include <algorithm>

namespace xyla::timeline {

TimelineTrackMetrics::TimelineTrackMetrics(int defaultHeight)
    : m_defaultHeight(defaultHeight > 0 ? defaultHeight : 68) {}

void TimelineTrackMetrics::setTrackCount(size_t count) {
  if (m_heights.size() == count) {
    return;
  }

  // preserve existing heights and fill newly added tracks with default height
  m_heights.resize(count, m_defaultHeight);
  recalculateOffsets();
}

bool TimelineTrackMetrics::setTrackHeight(int trackIndex, int height) {
  if (trackIndex < 0 || static_cast<size_t>(trackIndex) >= m_heights.size() ||
      height <= 0) {
    return false;
  }

  if (m_heights[static_cast<size_t>(trackIndex)] == height) {
    return false;
  }

  m_heights[static_cast<size_t>(trackIndex)] = height;
  recalculateOffsets();
  return true;
}

int TimelineTrackMetrics::trackHeight(int trackIndex) const noexcept {
  if (trackIndex < 0 || static_cast<size_t>(trackIndex) >= m_heights.size()) {
    return m_defaultHeight;
  }

  return m_heights[static_cast<size_t>(trackIndex)];
}

int TimelineTrackMetrics::trackY(int trackIndex) const noexcept {
  if (trackIndex < 0) {
    return 0;
  }

  if (static_cast<size_t>(trackIndex) < m_offsets.size()) {
    return m_offsets[static_cast<size_t>(trackIndex)];
  }

  // extrapolate position beyond configured tracks using default row height
  const int extraTracks = trackIndex - static_cast<int>(m_offsets.size());
  return m_totalHeight + (extraTracks * m_defaultHeight);
}

int TimelineTrackMetrics::trackAtY(int canvasY) const noexcept {
  if (m_offsets.empty() || canvasY <= 0) {
    return 0;
  }

  if (canvasY >= m_totalHeight) {
    return static_cast<int>(m_offsets.size()) - 1;
  }

  // find matching track interval via binary search over prefix offsets
  auto it = std::upper_bound(m_offsets.begin(), m_offsets.end(), canvasY);
  const int index = static_cast<int>(std::distance(m_offsets.begin(), it)) - 1;

  return std::clamp(index, 0, static_cast<int>(m_offsets.size()) - 1);
}

void TimelineTrackMetrics::recalculateOffsets() {
  m_offsets.resize(m_heights.size());

  int accumulator = 0;
  for (size_t i = 0; i < m_heights.size(); ++i) {
    m_offsets[i] = accumulator;
    accumulator += m_heights[i];
  }

  m_totalHeight = accumulator;
}

} // namespace xyla::timeline
