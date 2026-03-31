import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'cloud_api_service.dart';
import 'data_sources.dart';
import 'models.dart';

class MonitorController extends ChangeNotifier {
  MonitorController()
      : mqttConfig = MqttAdapterConfig(),
        bluetoothConfig = BluetoothAdapterConfig(),
        cloudApi = CloudApiService(baseUrl: 'http://127.0.0.1:8000') {
    _mqttAdapter = MqttDataSourceAdapter(mqttConfig);
    _fileAdapter = FileReplayAdapter();
    _bluetoothAdapter = BluetoothDataSourceAdapter(bluetoothConfig);
    _bindAdapter(_mqttAdapter);
  }

  final Uuid _uuid = const Uuid();

  final MqttAdapterConfig mqttConfig;
  final BluetoothAdapterConfig bluetoothConfig;
  final CloudApiService cloudApi;

  late final MqttDataSourceAdapter _mqttAdapter;
  late final FileReplayAdapter _fileAdapter;
  late final BluetoothDataSourceAdapter _bluetoothAdapter;

  DataSourceMode mode = DataSourceMode.wifi;
  DataSourceAdapter? _currentAdapter;
  StreamSubscription<SignalFrame>? _frameSubscription;
  StreamSubscription<AdapterStatus>? _statusSubscription;
  StreamSubscription<List<ChannelDescriptor>>? _catalogSubscription;
  Timer? _notifyTimer;

  final List<String> _events = <String>[];
  final Map<String, WaveformBuffer> _buffers = <String, WaveformBuffer>{};
  List<ChannelDescriptor> _channelCatalog = <ChannelDescriptor>[];

  AdapterStatus status = AdapterStatus(
    state: AdapterState.idle,
    message: '等待连接',
    updatedAt: DateTime.now(),
  );

  SessionRecord? session;
  UploadTask? uploadTask;
  AnalysisJob? analysisJob;
  MedicalReport? report;

  int latestTimestampMs = 0;
  int? _pauseReferenceTimestampMs;
  bool isPaused = false;
  double secondsPerScreen = 8;
  double historyOffsetSeconds = 0;
  double gain = 1;

  String cloudBaseUrl = 'http://127.0.0.1:8000';

  List<String> get events => List<String>.unmodifiable(_events);
  List<ChannelDescriptor> get channelCatalog =>
      List<ChannelDescriptor>.unmodifiable(_channelCatalog);
  List<ChannelDescriptor> get visibleChannels =>
      _channelCatalog.where((ChannelDescriptor item) => item.enabled).toList();
  String get replayFileName => _fileAdapter.replayFileName;
  bool get hasReplayFile => _fileAdapter.isLoaded;
  bool get isConnected =>
      status.state == AdapterState.connected || status.state == AdapterState.streaming;
  bool get canRollbackHistory => isPaused && maxHistoryOffsetSeconds > 0.05;

  int get currentAnchorTimestampMs {
    final liveBase = latestTimestampMs == 0
        ? DateTime.now().millisecondsSinceEpoch
        : latestTimestampMs;
    if (!isPaused) {
      return liveBase;
    }
    final pauseBase = _pauseReferenceTimestampMs ?? liveBase;
    return pauseBase - (historyOffsetSeconds * 1000).round();
  }

  LocalAnalysisSnapshot get localAnalysis => _buildLocalAnalysis();

  Future<void> setMode(DataSourceMode nextMode) async {
    if (mode == nextMode) {
      return;
    }
    await disconnect();
    mode = nextMode;
    if (nextMode == DataSourceMode.wifi) {
      _bindAdapter(_mqttAdapter);
    } else if (nextMode == DataSourceMode.file) {
      _bindAdapter(_fileAdapter);
    } else {
      _bindAdapter(_bluetoothAdapter);
    }
    _pushEvent('切换为 ${nextMode.label} 模式');
    _scheduleNotify();
  }

  void updateMqttConfig({
    String? host,
    int? port,
    String? path,
    bool? useTls,
    String? deviceId,
    String? username,
    String? password,
  }) {
    if (host != null) {
      mqttConfig.host = host;
    }
    if (port != null) {
      mqttConfig.port = port;
    }
    if (path != null) {
      mqttConfig.path = path;
    }
    if (useTls != null) {
      mqttConfig.useTls = useTls;
    }
    if (deviceId != null) {
      mqttConfig.deviceId = deviceId;
    }
    if (username != null) {
      mqttConfig.username = username;
    }
    if (password != null) {
      mqttConfig.password = password;
    }
    _scheduleNotify();
  }

  void updateBluetoothConfig({
    String? deviceNamePrefix,
    String? serviceUuid,
    String? notifyCharacteristicUuid,
    String? controlCharacteristicUuid,
  }) {
    if (deviceNamePrefix != null) {
      bluetoothConfig.deviceNamePrefix = deviceNamePrefix;
    }
    if (serviceUuid != null) {
      bluetoothConfig.serviceUuid = serviceUuid;
    }
    if (notifyCharacteristicUuid != null) {
      bluetoothConfig.notifyCharacteristicUuid = notifyCharacteristicUuid;
    }
    if (controlCharacteristicUuid != null) {
      bluetoothConfig.controlCharacteristicUuid = controlCharacteristicUuid;
    }
    _scheduleNotify();
  }

  void updateCloudBaseUrl(String value) {
    cloudBaseUrl = value.trim();
    cloudApi.baseUrl = cloudBaseUrl;
    _scheduleNotify();
  }

  Future<void> pickReplayFile() async {
    await _fileAdapter.pickFile();
    if (_fileAdapter.parsedChannels.isNotEmpty) {
      _pushEvent('已选择回放文件 ${_fileAdapter.replayFileName}');
      _scheduleNotify();
    }
  }

  Future<void> connect() async {
    final adapter = _currentAdapter;
    if (adapter == null) {
      return;
    }

    if (mode == DataSourceMode.file && !_fileAdapter.isLoaded) {
      await pickReplayFile();
      if (!_fileAdapter.isLoaded) {
        return;
      }
    }

    if (_channelCatalog.isNotEmpty) {
      await adapter.updateChannels(_channelCatalog);
    }

    _buffers.clear();
    report = null;
    uploadTask = null;
    analysisJob = null;
    latestTimestampMs = 0;
    isPaused = false;
    historyOffsetSeconds = 0;
    _pauseReferenceTimestampMs = null;
    session = SessionRecord(
      id: _uuid.v4(),
      deviceId: mode == DataSourceMode.wifi
          ? mqttConfig.deviceId
          : mode == DataSourceMode.bluetooth
              ? bluetoothConfig.deviceNamePrefix
              : 'local-replay',
      sourceMode: mode.name,
      startedAt: DateTime.now().toUtc().toIso8601String(),
      channelKeys: _channelCatalog.map((ChannelDescriptor item) => item.key).toList(),
    );

    _pushEvent('开始新的监测会话 ${session!.id}');
    _scheduleNotify();
    await adapter.connect();
  }

  Future<void> disconnect() async {
    isPaused = false;
    historyOffsetSeconds = 0;
    _pauseReferenceTimestampMs = null;
    await _currentAdapter?.disconnect();
    _scheduleNotify();
  }

  Future<void> toggleChannel(String key, bool enabled) async {
    final updated = _channelCatalog
        .map(
          (ChannelDescriptor item) =>
              item.key == key ? item.copyWith(enabled: enabled) : item,
        )
        .toList();
    _setCatalog(updated);
    await _currentAdapter?.updateChannels(updated);
    _pushEvent('${enabled ? '启用' : '禁用'}通道 $key');
    _scheduleNotify();
  }

  void setSecondsPerScreen(double value) {
    secondsPerScreen = value;
    if (isPaused) {
      historyOffsetSeconds = historyOffsetSeconds.clamp(0.0, maxHistoryOffsetSeconds);
    } else {
      historyOffsetSeconds = 0;
    }
    _scheduleNotify();
  }

  void setHistoryOffsetSeconds(double value) {
    if (!isPaused) {
      historyOffsetSeconds = 0;
      _scheduleNotify();
      return;
    }
    historyOffsetSeconds = value.clamp(0.0, maxHistoryOffsetSeconds);
    _scheduleNotify();
  }

  void setGain(double value) {
    gain = value;
    _scheduleNotify();
  }

  void togglePause() {
    if (isPaused) {
      isPaused = false;
      historyOffsetSeconds = 0;
      _pauseReferenceTimestampMs = null;
      _pushEvent('恢复实时播放，并跳转到最新位置');
    } else {
      isPaused = true;
      historyOffsetSeconds = 0;
      _pauseReferenceTimestampMs = latestTimestampMs == 0
          ? DateTime.now().millisecondsSinceEpoch
          : latestTimestampMs;
      _pushEvent('已暂停实时播放，可自由回滚查看历史波形');
    }
    _scheduleNotify();
  }

  double get maxHistoryOffsetSeconds {
    final reference = isPaused
        ? (_pauseReferenceTimestampMs ?? latestTimestampMs)
        : latestTimestampMs;
    if (_buffers.isEmpty || reference == 0) {
      return 0;
    }
    final candidates = _buffers.values
        .where((WaveformBuffer item) => item.hasPoints)
        .map((WaveformBuffer item) => item.oldestTimestampMs)
        .toList();
    if (candidates.isEmpty) {
      return 0;
    }
    final oldest = candidates.reduce(math.min);
    final span = reference - oldest;
    return math.max(0, span / 1000 - secondsPerScreen).toDouble();
  }

  List<SamplePoint> visiblePoints(String channelKey) {
    final buffer = _buffers[channelKey];
    if (buffer == null) {
      return const <SamplePoint>[];
    }
    return buffer.visiblePoints(
      anchorMs: currentAnchorTimestampMs,
      windowMs: (secondsPerScreen * 1000).round(),
    );
  }

  Map<String, dynamic> channelSummary(String channelKey) {
    return _buffers[channelKey]?.summary() ?? const <String, dynamic>{};
  }

  Future<void> uploadAndAnalyze() async {
    final localSession = session;
    if (localSession == null || _buffers.isEmpty) {
      _pushEvent('当前没有可上传的数据');
      _scheduleNotify();
      return;
    }

    try {
      cloudApi.baseUrl = cloudBaseUrl;
      _pushEvent('开始上传监测摘要到云端');

      final cloudSession = await cloudApi.createSession(localSession);
      session = cloudSession;

      final summary = _buildSummaryPayload();
      final excerpts = _buildExcerptPayload();
      uploadTask = await cloudApi.uploadSessionData(
        sessionId: cloudSession.id,
        summary: summary,
        excerpts: excerpts,
      );
      _pushEvent('摘要上传完成，任务 ${uploadTask!.id}');

      analysisJob = await cloudApi.createAnalysisJob(cloudSession.id);
      _pushEvent('分析任务已创建 ${analysisJob!.id}');

      for (var attempt = 0; attempt < 6; attempt++) {
        analysisJob = await cloudApi.getAnalysisJob(analysisJob!.id);
        if (analysisJob!.status == 'completed') {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }

      report = await cloudApi.getReport(cloudSession.id);
      _pushEvent('云端报告已回传');
    } catch (error) {
      _pushEvent('上传或分析失败: $error');
      status = AdapterStatus(
        state: AdapterState.error,
        message: '上传或分析失败: $error',
        updatedAt: DateTime.now(),
      );
    }

    _scheduleNotify();
  }

  void _bindAdapter(DataSourceAdapter adapter) {
    _frameSubscription?.cancel();
    _statusSubscription?.cancel();
    _catalogSubscription?.cancel();
    _currentAdapter = adapter;
    _frameSubscription = adapter.streamFrames.listen(_onFrame);
    _statusSubscription = adapter.streamStatus.listen(_onStatus);
    _catalogSubscription = adapter.streamCatalog.listen(_onCatalog);
  }

  void _onCatalog(List<ChannelDescriptor> channels) {
    _setCatalog(channels);
    _pushEvent('目录同步完成，共 ${channels.length} 个通道');
    _scheduleNotify();
  }

  void _onFrame(SignalFrame frame) {
    latestTimestampMs = latestTimestampMs == 0
        ? frame.timestampMs
        : math.max(latestTimestampMs, frame.timestampMs);
    if (_channelCatalog.every((ChannelDescriptor item) => item.key != frame.channelKey)) {
      _mergeFrameChannel(frame);
    }
    final buffer = _buffers.putIfAbsent(
      frame.channelKey,
      () => WaveformBuffer(channelKey: frame.channelKey),
    );
    buffer.appendFrame(frame);
    _scheduleNotify();
  }

  void _onStatus(AdapterStatus nextStatus) {
    status = nextStatus;
    _pushEvent(nextStatus.message);
    _scheduleNotify();
  }

  void _setCatalog(List<ChannelDescriptor> channels) {
    _channelCatalog = List<ChannelDescriptor>.from(channels);
    for (final ChannelDescriptor item in _channelCatalog) {
      _buffers.putIfAbsent(item.key, () => WaveformBuffer(channelKey: item.key));
    }
    if (session != null) {
      session = SessionRecord(
        id: session!.id,
        deviceId: session!.deviceId,
        sourceMode: session!.sourceMode,
        startedAt: session!.startedAt,
        channelKeys: _channelCatalog.map((ChannelDescriptor item) => item.key).toList(),
      );
    }
  }

  void _mergeFrameChannel(SignalFrame frame) {
    final inferred = ChannelDescriptor(
      key: frame.channelKey,
      label: frame.channelKey.toUpperCase(),
      unit: frame.unit,
      sampleRate: frame.sampleRate,
      colorHex: '#247BA0',
      enabled: true,
    );
    _setCatalog(<ChannelDescriptor>[..._channelCatalog, inferred]);
  }

  Map<String, dynamic> _buildSummaryPayload() {
    final snapshot = localAnalysis;
    final channelSummaries = <String, dynamic>{};
    for (final ChannelDescriptor descriptor in _channelCatalog) {
      final summary = _buffers[descriptor.key]?.summary();
      if (summary == null || summary.isEmpty) {
        continue;
      }
      channelSummaries[descriptor.key] = summary;
    }

    return <String, dynamic>{
      'durationSeconds': snapshot.durationSeconds,
      'qualityScore': snapshot.meanQuality,
      'channels': channelSummaries,
      'mode': mode.name,
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'localAnalysis': <String, dynamic>{
        'activeChannels': snapshot.activeChannels,
        'durationSeconds': snapshot.durationSeconds,
        'meanQuality': snapshot.meanQuality,
        'findings': snapshot.findings,
        'channels': snapshot.channels
            .map(
              (LocalChannelAnalysis item) => <String, dynamic>{
                'channelKey': item.channelKey,
                'label': item.label,
                'unit': item.unit,
                'sampleCount': item.sampleCount,
                'durationSeconds': item.durationSeconds,
                'mean': item.mean,
                'min': item.min,
                'max': item.max,
                'rms': item.rms,
                'stdDev': item.stdDev,
                'peakToPeak': item.peakToPeak,
                'meanQuality': item.meanQuality,
                'estimatedRateBpm': item.estimatedRateBpm,
                'notes': item.notes,
              },
            )
            .toList(),
      },
    };
  }

  Map<String, dynamic> _buildExcerptPayload() {
    final excerpts = <String, dynamic>{};
    for (final ChannelDescriptor descriptor
        in _channelCatalog.where((ChannelDescriptor item) => item.enabled)) {
      final buffer = _buffers[descriptor.key];
      if (buffer == null || !buffer.hasPoints) {
        continue;
      }
      excerpts[descriptor.key] = buffer.tailValues(maxItems: 24);
    }
    return excerpts;
  }

  LocalAnalysisSnapshot _buildLocalAnalysis() {
    final channels = <LocalChannelAnalysis>[];
    final findings = <String>[];
    var qualityAccumulator = 0.0;
    var qualityCount = 0;
    var longestDuration = 0.0;

    for (final ChannelDescriptor descriptor
        in _channelCatalog.where((ChannelDescriptor item) => item.enabled)) {
      final summary = _buffers[descriptor.key]?.summary();
      if (summary == null || summary.isEmpty) {
        continue;
      }

      final durationSeconds = _asDouble(summary['durationSeconds']);
      final meanQuality = _asDouble(summary['meanQuality']);
      final estimatedRate = _asNullableDouble(summary['estimatedRateBpm']);
      final notes = <String>[];

      if (durationSeconds < math.max(4, secondsPerScreen / 2)) {
        notes.add('数据时长偏短');
      }
      if (meanQuality < 0.75) {
        notes.add('平均质量偏低');
      }
      if (estimatedRate != null) {
        notes.add('估计节律 ${estimatedRate.toStringAsFixed(1)} BPM');
      }
      if (descriptor.key.contains('spo2')) {
        notes.add('可用于血氧趋势预览');
      }
      if (descriptor.key.contains('temp')) {
        notes.add('可用于体温趋势预览');
      }

      channels.add(
        LocalChannelAnalysis(
          channelKey: descriptor.key,
          label: descriptor.label,
          unit: descriptor.unit,
          sampleCount: (summary['samples'] as num? ?? 0).toInt(),
          durationSeconds: durationSeconds,
          mean: _asDouble(summary['mean']),
          min: _asDouble(summary['min']),
          max: _asDouble(summary['max']),
          rms: _asDouble(summary['rms']),
          stdDev: _asDouble(summary['stdDev']),
          peakToPeak: _asDouble(summary['peakToPeak']),
          meanQuality: meanQuality,
          estimatedRateBpm: estimatedRate,
          notes: notes,
        ),
      );

      qualityAccumulator += meanQuality;
      qualityCount += 1;
      longestDuration = math.max(longestDuration, durationSeconds);

      if (durationSeconds < 6) {
        findings.add('${descriptor.label} 当前缓存时长较短，更适合调试而非判读。');
      }
      if (estimatedRate != null) {
        findings.add('${descriptor.label} 检测到约 ${estimatedRate.toStringAsFixed(1)} BPM 的周期性变化。');
      }
      if (descriptor.key.contains('spo2')) {
        findings.add('${descriptor.label} 平均值约 ${_asDouble(summary['mean']).toStringAsFixed(1)} ${descriptor.unit}。');
      }
      if (descriptor.key.contains('temp')) {
        findings.add('${descriptor.label} 平均值约 ${_asDouble(summary['mean']).toStringAsFixed(2)} ${descriptor.unit}。');
      }
    }

    if (channels.isEmpty) {
      findings.add('尚未形成可用的本地统计结果，请先导入文件或连接设备。');
    } else {
      findings.insert(0, '本地区域已预留简单模型接口，可继续扩展去噪、峰值检测和节律分类。');
    }

    return LocalAnalysisSnapshot(
      activeChannels: channels.length,
      durationSeconds: longestDuration,
      meanQuality: qualityCount == 0 ? 0 : qualityAccumulator / qualityCount,
      channels: channels,
      findings: _deduplicateFindings(findings).take(8).toList(),
    );
  }

  List<String> _deduplicateFindings(List<String> findings) {
    final seen = <String>{};
    final ordered = <String>[];
    for (final String item in findings) {
      if (seen.add(item)) {
        ordered.add(item);
      }
    }
    return ordered;
  }

  double _asDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return 0;
  }

  double? _asNullableDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return null;
  }

  void _pushEvent(String message) {
    final now = DateTime.now();
    final stamp =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    _events.insert(0, '[$stamp] $message');
    if (_events.length > 60) {
      _events.removeLast();
    }
  }

  void _scheduleNotify() {
    if (_notifyTimer?.isActive ?? false) {
      return;
    }
    _notifyTimer = Timer(const Duration(milliseconds: 48), notifyListeners);
  }

  @override
  void dispose() {
    _notifyTimer?.cancel();
    _frameSubscription?.cancel();
    _statusSubscription?.cancel();
    _catalogSubscription?.cancel();
    _mqttAdapter.dispose();
    _fileAdapter.dispose();
    _bluetoothAdapter.dispose();
    cloudApi.dispose();
    super.dispose();
  }
}

class WaveformBuffer {
  WaveformBuffer({required this.channelKey});

  final String channelKey;
  final List<SamplePoint> _points = <SamplePoint>[];
  double _qualityWeighted = 0;
  int _qualitySamples = 0;
  double _sum = 0;
  double _sumSquares = 0;
  double _min = 0;
  double _max = 0;

  bool get hasPoints => _points.isNotEmpty;
  int get oldestTimestampMs => _points.isEmpty ? 0 : _points.first.timestampMs;

  void appendFrame(SignalFrame frame) {
    final stepMs = frame.sampleRate <= 0 ? 1 : (1000 / frame.sampleRate).round();
    for (var index = 0; index < frame.samples.length; index++) {
      final point = SamplePoint(
        timestampMs: frame.timestampMs + stepMs * index,
        value: frame.samples[index],
      );
      _appendPoint(point);
      _qualityWeighted += frame.quality;
      _qualitySamples += 1;
    }
    _trim();
  }

  List<SamplePoint> visiblePoints({
    required int anchorMs,
    required int windowMs,
  }) {
    if (_points.isEmpty) {
      return const <SamplePoint>[];
    }
    final start = anchorMs - windowMs;
    return _points
        .where(
          (SamplePoint point) =>
              point.timestampMs >= start && point.timestampMs <= anchorMs,
        )
        .toList();
  }

  Map<String, dynamic> summary() {
    if (_points.isEmpty) {
      return const <String, dynamic>{};
    }
    final sampleCount = _points.length;
    final mean = _sum / sampleCount;
    final rms = math.sqrt(_sumSquares / sampleCount);
    final variance = math.max(0, (_sumSquares / sampleCount) - mean * mean);
    final stdDev = math.sqrt(variance);
    final durationSeconds =
        (_points.last.timestampMs - _points.first.timestampMs) / 1000.0;

    return <String, dynamic>{
      'samples': sampleCount,
      'min': _min,
      'max': _max,
      'mean': mean,
      'rms': rms,
      'stdDev': stdDev,
      'peakToPeak': _max - _min,
      'durationSeconds': durationSeconds,
      'meanQuality': _qualitySamples == 0 ? 0 : _qualityWeighted / _qualitySamples,
      'estimatedRateBpm': _estimateRateBpm(mean: mean, durationSeconds: durationSeconds),
    };
  }

  List<double> tailValues({required int maxItems}) {
    final tail = _points.length <= maxItems
        ? _points
        : _points.sublist(_points.length - maxItems);
    return tail.map((SamplePoint item) => item.value).toList();
  }

  void _appendPoint(SamplePoint point) {
    if (_points.isEmpty) {
      _min = point.value;
      _max = point.value;
    } else {
      _min = math.min(_min, point.value);
      _max = math.max(_max, point.value);
    }
    _sum += point.value;
    _sumSquares += point.value * point.value;
    _points.add(point);
  }

  double? _estimateRateBpm({required double mean, required double durationSeconds}) {
    if (_points.length < 20 || durationSeconds < 3) {
      return null;
    }

    final dynamicRange = _max - _min;
    if (dynamicRange.abs() < 0.0001) {
      return null;
    }

    final threshold = mean + dynamicRange * 0.28;
    const minPeakDistanceMs = 280;
    final peakTimes = <int>[];

    for (var index = 1; index < _points.length - 1; index++) {
      final previous = _points[index - 1];
      final current = _points[index];
      final next = _points[index + 1];
      final isPeak = current.value > previous.value &&
          current.value >= next.value &&
          current.value >= threshold;
      if (!isPeak) {
        continue;
      }
      if (peakTimes.isNotEmpty &&
          current.timestampMs - peakTimes.last < minPeakDistanceMs) {
        if (current.value > _valueAtTimestamp(peakTimes.last)) {
          peakTimes[peakTimes.length - 1] = current.timestampMs;
        }
        continue;
      }
      peakTimes.add(current.timestampMs);
    }

    if (peakTimes.length < 2) {
      return null;
    }

    var totalInterval = 0;
    for (var index = 1; index < peakTimes.length; index++) {
      totalInterval += peakTimes[index] - peakTimes[index - 1];
    }
    final meanIntervalMs = totalInterval / (peakTimes.length - 1);
    if (meanIntervalMs <= 0) {
      return null;
    }

    final bpm = 60000 / meanIntervalMs;
    if (bpm < 25 || bpm > 240) {
      return null;
    }
    return bpm;
  }

  double _valueAtTimestamp(int timestampMs) {
    for (final SamplePoint point in _points) {
      if (point.timestampMs == timestampMs) {
        return point.value;
      }
    }
    return _points.last.value;
  }

  void _trim() {
    const maxRetainedPoints = 60000;
    if (_points.length <= maxRetainedPoints) {
      return;
    }
    final overflow = _points.length - maxRetainedPoints;
    final removed = _points.take(overflow).toList();
    for (final SamplePoint item in removed) {
      _sum -= item.value;
      _sumSquares -= item.value * item.value;
    }
    _points.removeRange(0, overflow);
    if (_points.isEmpty) {
      _min = 0;
      _max = 0;
      _sum = 0;
      _sumSquares = 0;
      return;
    }
    _min = _points.map((SamplePoint item) => item.value).reduce(math.min);
    _max = _points.map((SamplePoint item) => item.value).reduce(math.max);
  }
}

