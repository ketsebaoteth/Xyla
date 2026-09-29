#include "TimelineSequence.hpp"

#include <QJsonArray>
#include <QUuid>

namespace xyla::timeline {

TimelineSequence::TimelineSequence(QString id, QString name)
    : m_id(std::move(id)), m_name(std::move(name)),
      m_animationTable(std::make_shared<xyla::anim::AnimationPropertyTable>()) {
}

void TimelineSequence::createDefaultTracks(int videoCount, int audioCount) {
  m_tracks.clear();

  for (int i = 0; i < videoCount; ++i) {
    m_tracks.push_back(std::make_shared<xyla::TimelineTrack>(
        QUuid::createUuid().toString(QUuid::WithoutBraces),
        QString("Video %1").arg(videoCount - i), TrackKind::Video));
  }

  for (int i = 0; i < audioCount; ++i) {
    m_tracks.push_back(std::make_shared<xyla::TimelineTrack>(
        QUuid::createUuid().toString(QUuid::WithoutBraces),
        QString("Audio %1").arg(i + 1), TrackKind::Audio));
  }

  m_trackMetrics.setTrackCount(m_tracks.size());
}

void TimelineSequence::bindAnimationManager(
    xyla::anim::AnimationManager &animMgr) {
  for (auto &track : m_tracks) {
    if (!track) {
      continue;
    }
    for (const auto &clip : track->getClips()) {
      const_cast<xyla::TimelineClip &>(clip).bindAnimationManager(animMgr);
    }
  }
}

QJsonObject TimelineSequence::serialize() const {
  QJsonObject obj;
  obj[QStringLiteral("id")] = m_id;
  obj[QStringLiteral("name")] = m_name;
  obj[QStringLiteral("globalRippleMode")] = m_globalRippleMode;
  obj[QStringLiteral("snappingEnabled")] = m_snappingEnabled;
  obj[QStringLiteral("zoomFactor")] = m_zoomFactor;
  obj[QStringLiteral("horizontalOffset")] = m_horizontalOffset;
  obj[QStringLiteral("selectedTrackIndex")] = m_selectedTrackIndex;

  if (m_animationTable) {
    obj[QStringLiteral("animationTable")] = m_animationTable->serialize();
  }

  QJsonArray tracksArray;
  for (const auto &track : m_tracks) {
    if (track) {
      tracksArray.append(track->serialize());
    }
  }
  obj[QStringLiteral("tracks")] = tracksArray;
  obj[QStringLiteral("linkGraph")] = m_linkGraph.serialize();

  return obj;
}

std::unique_ptr<TimelineSequence>
TimelineSequence::deserialize(const QJsonObject &obj,
                              xyla::anim::AnimationManager *animMgr) {
  const QString id = obj.value(QStringLiteral("id")).toString();
  if (id.isEmpty()) {
    return nullptr;
  }

  const QString name =
      obj.value(QStringLiteral("name")).toString(QStringLiteral("Sequence"));
  auto seq = std::make_unique<TimelineSequence>(id, name);

  seq->setGlobalRippleMode(
      obj.value(QStringLiteral("globalRippleMode")).toBool(false));
  seq->setSnappingEnabled(
      obj.value(QStringLiteral("snappingEnabled")).toBool(true));
  seq->setZoomFactor(obj.value(QStringLiteral("zoomFactor")).toDouble(1.0));
  seq->setHorizontalOffset(
      obj.value(QStringLiteral("horizontalOffset")).toDouble(0.0));
  seq->setSelectedTrackIndex(
      obj.value(QStringLiteral("selectedTrackIndex")).toInt(-1));

  // restore animation property table for this sequence
  if (obj.contains(QStringLiteral("animationTable")) &&
      obj[QStringLiteral("animationTable")].isObject()) {
    seq->m_animationTable->deserialize(
        obj[QStringLiteral("animationTable")].toObject());
  }

  // restore tracks
  const QJsonArray tracksArray = obj.value(QStringLiteral("tracks")).toArray();
  for (const auto &trackVal : tracksArray) {
    if (trackVal.isObject()) {
      if (auto track = xyla::TimelineTrack::deserialize(trackVal.toObject())) {
        seq->m_tracks.push_back(std::move(track));
      }
    }
  }

  seq->m_trackMetrics.setTrackCount(seq->m_tracks.size());

  // bind clips to active animation manager if available
  if (animMgr) {
    seq->bindAnimationManager(*animMgr);
  }

  // restore link graph
  if (obj.contains(QStringLiteral("linkGraph")) &&
      obj[QStringLiteral("linkGraph")].isObject()) {
    seq->m_linkGraph.deserialize(obj[QStringLiteral("linkGraph")].toObject());
  }

  return seq;
}

} // namespace xyla::timeline
