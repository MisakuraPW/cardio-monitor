import 'package:flutter/material.dart';

enum DataSourceMode { bluetooth, wifi, file }

enum AdapterState { idle, connecting, connected, streaming, disconnected, error }

extension DataSourceModeX on DataSourceMode {
  String get label {
    switch (this) {
      case DataSourceMode.bluetooth:
        return '蓝牙';
      case DataSourceMode.wifi:
        return 'WiFi / MQTT';
      case DataSourceMode.file:
        return '数据文件';
    }
  }
}

class AdapterStatus {
  const AdapterStatus({
    required this.state,
    required this.message,
    required this.updatedAt,
  });

  final AdapterState state;
  final String message;
  final DateTime updatedAt;
}

class ChannelDescriptor {
  const ChannelDescriptor({
    required this.key,
    required this.label,
    required this.unit,
    required this.sampleRate,
    required this.colorHex,
    required this.enabled,
  });

  final String key;
  final String label;
  final String unit;
  final double sampleRate;
  final String colorHex;
  final bool enabled;

  ChannelDescriptor copyWith({
    String? key,
    String? label,
    String? unit,
    double? sampleRate,
    String? colorHex,
    bool? enabled,
  }) {
    return ChannelDescriptor(
      key: key ?? this.key,
      label: label ?? this.label,
      unit: unit ?? this.unit,
      sampleRate: sampleRate ?? this.sampleRate,
      colorHex: colorHex ?? this.colorHex,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'key': key,
      'label': label,
      'unit': unit,
      'sampleRate': sampleRate,
      'colorHex': colorHex,
      'enabled': enabled,
    };
  }

  factory ChannelDescriptor.fromJson(Map<String, dynamic> json) {
    return ChannelDescriptor(
      key: json['key'] as String,
      label: (json['label'] ?? json['key']) as String,
      unit: (json['unit'] ?? 'a.u.') as String,
      sampleRate: (json['sampleRate'] as num?)?.toDouble() ?? 0,
      colorHex: (json['colorHex'] ?? '#2F6690') as String,
      enabled: (json['enabled'] as bool?) ?? true,
    );
  }
}

class SignalFrame {
  const SignalFrame({
    required this.deviceId,
    required this.sessionId,
    required this.seq,
    required this.timestampMs,
    required this.channelKey,
    required this.sampleRate,
    required this.unit,
    required this.quality,
    required this.samples,
  });

  final String deviceId;
  final String sessionId;
  final int seq;
  final int timestampMs;
  final String channelKey;
  final double sampleRate;
  final String unit;
  final double quality;
  final List<double> samples;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'deviceId': deviceId,
      'sessionId': sessionId,
      'seq': seq,
      'timestampMs': timestampMs,
      'channelKey': channelKey,
      'sampleRate': sampleRate,
      'unit': unit,
      'quality': quality,
      'samples': samples,
    };
  }

  factory SignalFrame.fromJson(Map<String, dynamic> json) {
    final rawSamples = json['samples'] as List<dynamic>? ?? const <dynamic>[];
    return SignalFrame(
      deviceId: (json['deviceId'] ?? 'unknown-device') as String,
      sessionId: (json['sessionId'] ?? 'unknown-session') as String,
      seq: (json['seq'] as num?)?.toInt() ?? 0,
      timestampMs: (json['timestampMs'] as num).toInt(),
      channelKey: json['channelKey'] as String,
      sampleRate: (json['sampleRate'] as num?)?.toDouble() ?? 0,
      unit: (json['unit'] ?? 'a.u.') as String,
      quality: (json['quality'] as num?)?.toDouble() ?? 1.0,
      samples: rawSamples.map((dynamic item) => (item as num).toDouble()).toList(),
    );
  }
}

class ControlCommand {
  const ControlCommand({
    required this.type,
    required this.payload,
  });

  final String type;
  final Map<String, dynamic> payload;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': type,
      'payload': payload,
    };
  }
}

class SessionRecord {
  const SessionRecord({
    required this.id,
    required this.deviceId,
    required this.sourceMode,
    required this.startedAt,
    required this.channelKeys,
  });

  final String id;
  final String deviceId;
  final String sourceMode;
  final String startedAt;
  final List<String> channelKeys;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'deviceId': deviceId,
      'sourceMode': sourceMode,
      'startedAt': startedAt,
      'channelKeys': channelKeys,
    };
  }

  factory SessionRecord.fromJson(Map<String, dynamic> json) {
    final keys = (json['channelKeys'] as List<dynamic>? ?? const <dynamic>[])
        .map((dynamic item) => item.toString())
        .toList();
    return SessionRecord(
      id: json['id'] as String,
      deviceId: json['deviceId'] as String,
      sourceMode: json['sourceMode'] as String,
      startedAt: json['startedAt'] as String,
      channelKeys: keys,
    );
  }
}

class UploadTask {
  const UploadTask({
    required this.id,
    required this.sessionId,
    required this.status,
    required this.createdAt,
    required this.lastMessage,
  });

  final String id;
  final String sessionId;
  final String status;
  final String createdAt;
  final String lastMessage;

  factory UploadTask.fromJson(Map<String, dynamic> json) {
    return UploadTask(
      id: json['id'] as String,
      sessionId: json['sessionId'] as String,
      status: json['status'] as String,
      createdAt: json['createdAt'] as String,
      lastMessage: (json['lastMessage'] ?? '') as String,
    );
  }
}

class AnalysisJob {
  const AnalysisJob({
    required this.id,
    required this.sessionId,
    required this.status,
    required this.createdAt,
    required this.completedAt,
    required this.summary,
  });

  final String id;
  final String sessionId;
  final String status;
  final String createdAt;
  final String? completedAt;
  final String summary;

  factory AnalysisJob.fromJson(Map<String, dynamic> json) {
    return AnalysisJob(
      id: json['id'] as String,
      sessionId: json['sessionId'] as String,
      status: json['status'] as String,
      createdAt: json['createdAt'] as String,
      completedAt: json['completedAt'] as String?,
      summary: (json['summary'] ?? '') as String,
    );
  }
}

class ReportFinding {
  const ReportFinding({
    required this.title,
    required this.severity,
    required this.detail,
  });

  final String title;
  final String severity;
  final String detail;

  factory ReportFinding.fromJson(Map<String, dynamic> json) {
    return ReportFinding(
      title: json['title'] as String,
      severity: json['severity'] as String,
      detail: json['detail'] as String,
    );
  }
}

class MedicalReport {
  const MedicalReport({
    required this.sessionId,
    required this.generatedAt,
    required this.summary,
    required this.recommendations,
    required this.findings,
  });

  final String sessionId;
  final String generatedAt;
  final String summary;
  final List<String> recommendations;
  final List<ReportFinding> findings;

  factory MedicalReport.fromJson(Map<String, dynamic> json) {
    final recommendations =
        (json['recommendations'] as List<dynamic>? ?? const <dynamic>[])
            .map((dynamic item) => item.toString())
            .toList();
    final findings = (json['findings'] as List<dynamic>? ?? const <dynamic>[])
        .map(
          (dynamic item) => ReportFinding.fromJson(item as Map<String, dynamic>),
        )
        .toList();
    return MedicalReport(
      sessionId: json['sessionId'] as String,
      generatedAt: json['generatedAt'] as String,
      summary: (json['summary'] ?? '') as String,
      recommendations: recommendations,
      findings: findings,
    );
  }
}

class SamplePoint {
  const SamplePoint({
    required this.timestampMs,
    required this.value,
  });

  final int timestampMs;
  final double value;
}

class WaveformSlice {
  const WaveformSlice({
    required this.points,
    required this.minValue,
    required this.maxValue,
  });

  static const WaveformSlice empty = WaveformSlice(
    points: <SamplePoint>[],
    minValue: 0,
    maxValue: 0,
  );

  final List<SamplePoint> points;
  final double minValue;
  final double maxValue;

  bool get isEmpty => points.isEmpty;
}

class HoverSampleInfo {
  const HoverSampleInfo({
    required this.sample,
    required this.localDx,
    required this.localDy,
  });

  final SamplePoint sample;
  final double localDx;
  final double localDy;
}

class LocalChannelAnalysis {
  const LocalChannelAnalysis({
    required this.channelKey,
    required this.label,
    required this.unit,
    required this.sampleCount,
    required this.durationSeconds,
    required this.mean,
    required this.min,
    required this.max,
    required this.rms,
    required this.stdDev,
    required this.peakToPeak,
    required this.meanQuality,
    required this.estimatedRateBpm,
    required this.notes,
  });

  final String channelKey;
  final String label;
  final String unit;
  final int sampleCount;
  final double durationSeconds;
  final double mean;
  final double min;
  final double max;
  final double rms;
  final double stdDev;
  final double peakToPeak;
  final double meanQuality;
  final double? estimatedRateBpm;
  final List<String> notes;
}

class LocalAnalysisSnapshot {
  const LocalAnalysisSnapshot({
    required this.activeChannels,
    required this.durationSeconds,
    required this.meanQuality,
    required this.channels,
    required this.findings,
  });

  final int activeChannels;
  final double durationSeconds;
  final double meanQuality;
  final List<LocalChannelAnalysis> channels;
  final List<String> findings;
}

Color colorFromHex(String hex) {
  final normalized = hex.replaceFirst('#', '');
  final buffer = StringBuffer();
  if (normalized.length == 6) {
    buffer.write('FF');
  }
  buffer.write(normalized);
  return Color(int.parse(buffer.toString(), radix: 16));
}
