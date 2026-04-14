// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use, uri_does_not_exist
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

abstract class DataSourceAdapter {
  Stream<SignalFrame> get streamFrames;
  Stream<AdapterStatus> get streamStatus;
  Stream<List<ChannelDescriptor>> get streamCatalog;

  Future<void> connect();
  Future<void> disconnect();
  Future<void> updateChannels(List<ChannelDescriptor> channels);
  Future<void> sendControl(ControlCommand command);
  void dispose();
}

class MqttAdapterConfig {
  MqttAdapterConfig({
    this.host = '127.0.0.1',
    this.port = 9001,
    this.path = '/mqtt',
    this.useTls = false,
    this.deviceId = 'esp32-demo-01',
    this.username = '',
    this.password = '',
  });

  String host;
  int port;
  String path;
  bool useTls;
  String deviceId;
  String username;
  String password;
}

class BluetoothAdapterConfig {
  BluetoothAdapterConfig({
    this.deviceNamePrefix = 'esp32-bio',
    this.serviceUuid = 'c0ad0001-8d2b-4d6f-9a1c-1c8a52f0a001',
    this.notifyCharacteristicUuid = 'c0ad1001-8d2b-4d6f-9a1c-1c8a52f0a001',
    this.controlCharacteristicUuid = 'c0ad1002-8d2b-4d6f-9a1c-1c8a52f0a001',
  });

  String deviceNamePrefix;
  String serviceUuid;
  String notifyCharacteristicUuid;
  String controlCharacteristicUuid;
}

class MqttDataSourceAdapter implements DataSourceAdapter {
  MqttDataSourceAdapter(this.config);

  final MqttAdapterConfig config;
  final StreamController<SignalFrame> _frameController =
      StreamController<SignalFrame>.broadcast();
  final StreamController<AdapterStatus> _statusController =
      StreamController<AdapterStatus>.broadcast();
  final StreamController<List<ChannelDescriptor>> _catalogController =
      StreamController<List<ChannelDescriptor>>.broadcast();
  final Uuid _uuid = const Uuid();

  MqttBrowserClient? _client;
  List<ChannelDescriptor> catalog = const <ChannelDescriptor>[];

  String get _baseTopic => 'cardio/${config.deviceId}';

  @override
  Stream<SignalFrame> get streamFrames => _frameController.stream;

  @override
  Stream<AdapterStatus> get streamStatus => _statusController.stream;

  @override
  Stream<List<ChannelDescriptor>> get streamCatalog => _catalogController.stream;

  @override
  Future<void> connect() async {
    await disconnect();
    _emitStatus(AdapterState.connecting, '正在连接 MQTT Broker...');

    final protocol = config.useTls ? 'wss' : 'ws';
    final endpoint = '$protocol://${config.host}:${config.port}${config.path}';
    final clientId = 'flutter-web-${_uuid.v4().substring(0, 8)}';

    final client = MqttBrowserClient(endpoint, clientId);
    client.keepAlivePeriod = 20;
    client.logging(on: false);
    client.websocketProtocols = const <String>['mqtt'];
    client.onConnected = () {
      _emitStatus(AdapterState.connected, 'MQTT 连接已建立');
    };
    client.onDisconnected = () {
      _emitStatus(AdapterState.disconnected, 'MQTT 连接已断开');
    };
    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);

    try {
      if (config.username.isNotEmpty) {
        await client.connect(
          config.username,
          config.password.isEmpty ? null : config.password,
        );
      } else {
        await client.connect();
      }
    } catch (error) {
      _emitStatus(AdapterState.error, 'MQTT 连接失败: $error');
      rethrow;
    }

    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      final state = client.connectionStatus?.state.toString() ?? 'unknown';
      _emitStatus(AdapterState.error, 'MQTT 未连接成功: $state');
      throw Exception('MQTT connection failed: $state');
    }

    _client = client;
    client.subscribe('$_baseTopic/status', MqttQos.atLeastOnce);
    client.subscribe('$_baseTopic/catalog', MqttQos.atLeastOnce);
    client.subscribe('$_baseTopic/waveform/+', MqttQos.atMostOnce);
    client.subscribe('$_baseTopic/metrics', MqttQos.atLeastOnce);
    client.subscribe('$_baseTopic/alerts', MqttQos.atLeastOnce);
    client.updates?.listen(_handleUpdates);

    _emitStatus(AdapterState.streaming, '正在监听 $_baseTopic/#');
  }

  @override
  Future<void> disconnect() async {
    _client?.disconnect();
    _client = null;
  }

  @override
  Future<void> updateChannels(List<ChannelDescriptor> channels) async {
    catalog = List<ChannelDescriptor>.from(channels);
    final enabledKeys = channels
        .where((ChannelDescriptor item) => item.enabled)
        .map((ChannelDescriptor item) => item.key)
        .toList();
    await sendControl(
      ControlCommand(
        type: 'set_channels',
        payload: <String, dynamic>{'enabledKeys': enabledKeys},
      ),
    );
  }

  @override
  Future<void> sendControl(ControlCommand command) async {
    final client = _client;
    if (client == null) {
      return;
    }
    final builder = MqttClientPayloadBuilder();
    builder.addUTF8String(jsonEncode(command.toJson()));
    client.publishMessage(
      '$_baseTopic/control',
      MqttQos.atLeastOnce,
      builder.payload!,
    );
  }

  void _handleUpdates(List<MqttReceivedMessage<MqttMessage>>? events) {
    if (events == null) {
      return;
    }
    for (final MqttReceivedMessage<MqttMessage> event in events) {
      final topic = event.topic;
      final publishMessage = event.payload as MqttPublishMessage;
      final payload = MqttPublishPayload.bytesToStringAsString(
        publishMessage.payload.message,
      );
      if (payload.trim().isEmpty) {
        continue;
      }

      final Map<String, dynamic> jsonMap =
          jsonDecode(payload) as Map<String, dynamic>;
      if (topic.endsWith('/catalog')) {
        final rawChannels =
            (jsonMap['channels'] as List<dynamic>? ?? const <dynamic>[]);
        catalog = rawChannels
            .map(
              (dynamic item) =>
                  ChannelDescriptor.fromJson(item as Map<String, dynamic>),
            )
            .toList();
        _catalogController.add(List<ChannelDescriptor>.from(catalog));
        _emitStatus(
          AdapterState.streaming,
          '已收到通道目录更新，共 ${catalog.length} 个通道',
        );
        continue;
      }

      if (topic.contains('/waveform/')) {
        final frameJson = <String, dynamic>{...jsonMap};
        if (!frameJson.containsKey('channelKey')) {
          frameJson['channelKey'] = topic.split('/').last;
        }
        _frameController.add(SignalFrame.fromJson(frameJson));
        continue;
      }

      if (topic.endsWith('/status')) {
        final message = (jsonMap['message'] ?? '设备状态更新').toString();
        _emitStatus(AdapterState.streaming, message);
        continue;
      }

      if (topic.endsWith('/alerts')) {
        final message = (jsonMap['message'] ?? '收到报警事件').toString();
        _emitStatus(AdapterState.error, message);
      }
    }
  }

  void _emitStatus(AdapterState state, String message) {
    _statusController.add(
      AdapterStatus(
        state: state,
        message: message,
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  void dispose() {
    _frameController.close();
    _statusController.close();
    _catalogController.close();
  }
}

class FileReplayAdapter implements DataSourceAdapter {
  FileReplayAdapter();

  final StreamController<SignalFrame> _frameController =
      StreamController<SignalFrame>.broadcast();
  final StreamController<AdapterStatus> _statusController =
      StreamController<AdapterStatus>.broadcast();
  final StreamController<List<ChannelDescriptor>> _catalogController =
      StreamController<List<ChannelDescriptor>>.broadcast();
  final Uuid _uuid = const Uuid();

  final List<String> _palette = const <String>[
    '#F25F5C',
    '#247BA0',
    '#70C1B3',
    '#FF9F1C',
    '#6A4C93',
    '#0F4C5C',
  ];

  List<SignalFrame> _frames = <SignalFrame>[];
  Timer? _timer;
  DateTime? _replayStartAt;
  int _cursor = 0;
  Set<String> _enabledKeys = <String>{};

  List<ChannelDescriptor> parsedChannels = const <ChannelDescriptor>[];
  String replayFileName = '';

  bool get isLoaded => _frames.isNotEmpty;

  @override
  Stream<SignalFrame> get streamFrames => _frameController.stream;

  @override
  Stream<AdapterStatus> get streamStatus => _statusController.stream;

  @override
  Stream<List<ChannelDescriptor>> get streamCatalog => _catalogController.stream;

  Future<void> pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: const <String>['csv', 'json'],
    );
    if (result == null || result.files.isEmpty) {
      return;
    }
    await loadPlatformFile(result.files.single);
  }

  Future<void> loadPlatformFile(PlatformFile file) async {
    final bytes = file.bytes;
    if (bytes == null) {
      throw Exception('文件内容为空，Web 模式下请启用 withData');
    }

    replayFileName = file.name;
    final extension = file.extension?.toLowerCase() ?? '';
    if (extension == 'json') {
      await _loadJson(bytes);
    } else {
      await _loadCsv(bytes);
    }

    _enabledKeys = parsedChannels
        .where((ChannelDescriptor item) => item.enabled)
        .map((ChannelDescriptor item) => item.key)
        .toSet();
    _catalogController.add(List<ChannelDescriptor>.from(parsedChannels));
    _emitStatus(
      AdapterState.idle,
      '已载入文件 $replayFileName，共 ${parsedChannels.length} 个通道，${_frames.length} 帧',
    );
  }

  @override
  Future<void> connect() async {
    if (_frames.isEmpty) {
      _emitStatus(AdapterState.error, '请先选择 CSV 或 JSON 文件');
      throw Exception('Replay file is not loaded.');
    }

    await disconnect();
    _cursor = 0;
    _replayStartAt = DateTime.now();
    _emitStatus(AdapterState.streaming, '文件回放已开始');
    _timer = Timer.periodic(const Duration(milliseconds: 20), _onTick);
  }

  @override
  Future<void> disconnect() async {
    _timer?.cancel();
    _timer = null;
    if (_frames.isNotEmpty) {
      _emitStatus(AdapterState.disconnected, '文件回放已停止');
    }
  }

  @override
  Future<void> updateChannels(List<ChannelDescriptor> channels) async {
    parsedChannels = List<ChannelDescriptor>.from(channels);
    _enabledKeys = channels
        .where((ChannelDescriptor item) => item.enabled)
        .map((ChannelDescriptor item) => item.key)
        .toSet();
  }

  @override
  Future<void> sendControl(ControlCommand command) async {
    _emitStatus(AdapterState.streaming, '文件回放忽略控制指令: ${command.type}');
  }

  void _onTick(Timer timer) {
    if (_replayStartAt == null || _frames.isEmpty) {
      return;
    }

    final baseTimestamp = _frames.first.timestampMs;
    final elapsedMs = DateTime.now().difference(_replayStartAt!).inMilliseconds;
    while (_cursor < _frames.length) {
      final frame = _frames[_cursor];
      final relativeMs = frame.timestampMs - baseTimestamp;
      if (relativeMs > elapsedMs) {
        break;
      }
      if (_enabledKeys.isEmpty || _enabledKeys.contains(frame.channelKey)) {
        _frameController.add(frame);
      }
      _cursor++;
    }

    if (_cursor >= _frames.length) {
      _timer?.cancel();
      _emitStatus(AdapterState.disconnected, '文件回放完成');
    }
  }

  Future<void> _loadCsv(Uint8List bytes) async {
    final text = utf8.decode(bytes);
    final lines = const LineSplitter()
        .convert(text)
        .where((String line) => line.trim().isNotEmpty)
        .toList();
    if (lines.length < 2) {
      throw Exception('CSV 至少需要包含表头和一行数据');
    }

    final headers = _splitCsvLine(lines.first);
    final timestampIndex = headers.indexWhere(
      (String item) =>
          item.toLowerCase() == 'timestamp_ms' ||
          item.toLowerCase() == 'time_ms' ||
          item.toLowerCase() == 'time',
    );
    if (timestampIndex < 0) {
      throw Exception('CSV 缺少时间戳列，建议使用 timestamp_ms');
    }

    final channelColumns = <int, String>{};
    for (var index = 0; index < headers.length; index++) {
      if (index == timestampIndex) {
        continue;
      }
      channelColumns[index] = headers[index];
    }

    final timestamps = <int>[];
    final columns = <String, List<double>>{};
    for (final String header in channelColumns.values) {
      columns[header] = <double>[];
    }

    for (final String line in lines.skip(1)) {
      final parts = _splitCsvLine(line);
      if (parts.length != headers.length) {
        continue;
      }
      timestamps.add(int.parse(parts[timestampIndex]));
      channelColumns.forEach((int index, String header) {
        final value = double.tryParse(parts[index]) ?? 0;
        columns[header]!.add(value);
      });
    }

    if (timestamps.length < 2) {
      throw Exception('CSV 数据行过少，无法推断采样率');
    }

    final delta = timestamps[1] - timestamps[0];
    final sampleRate = delta <= 0 ? 100.0 : 1000.0 / delta;
    parsedChannels = <ChannelDescriptor>[];
    var colorIndex = 0;
    for (final entry in columns.entries) {
      final normalized = _normalizeHeader(entry.key);
      parsedChannels = <ChannelDescriptor>[
        ...parsedChannels,
        ChannelDescriptor(
          key: normalized.key,
          label: normalized.label,
          unit: normalized.unit,
          sampleRate: sampleRate,
          colorHex: _palette[colorIndex % _palette.length],
          enabled: true,
        ),
      ];
      colorIndex++;
    }

    _frames = _buildBatchedFrames(
      deviceId: 'file-device-${_uuid.v4().substring(0, 8)}',
      sessionId: 'file-session-${_uuid.v4().substring(0, 8)}',
      timestamps: timestamps,
      columns: columns,
      channelDescriptors: parsedChannels,
    );
  }

  Future<void> _loadJson(Uint8List bytes) async {
    final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final rawChannels =
        (decoded['channels'] as List<dynamic>? ?? const <dynamic>[]);
    final rawFrames = (decoded['frames'] as List<dynamic>? ?? const <dynamic>[]);
    parsedChannels = rawChannels
        .map(
          (dynamic item) =>
              ChannelDescriptor.fromJson(item as Map<String, dynamic>),
        )
        .toList();
    _frames = rawFrames
        .map(
          (dynamic item) => SignalFrame.fromJson(item as Map<String, dynamic>),
        )
        .toList()
      ..sort(
        (SignalFrame a, SignalFrame b) => a.timestampMs.compareTo(b.timestampMs),
      );

    if (parsedChannels.isEmpty && _frames.isNotEmpty) {
      final channels = <String, ChannelDescriptor>{};
      for (final SignalFrame frame in _frames) {
        channels[frame.channelKey] = ChannelDescriptor(
          key: frame.channelKey,
          label: frame.channelKey.toUpperCase(),
          unit: frame.unit,
          sampleRate: frame.sampleRate,
          colorHex: _palette[channels.length % _palette.length],
          enabled: true,
        );
      }
      parsedChannels = channels.values.toList();
    }
  }

  List<SignalFrame> _buildBatchedFrames({
    required String deviceId,
    required String sessionId,
    required List<int> timestamps,
    required Map<String, List<double>> columns,
    required List<ChannelDescriptor> channelDescriptors,
  }) {
    final frames = <SignalFrame>[];
    var seq = 0;

    for (final ChannelDescriptor descriptor in channelDescriptors) {
      final key = columns.keys.firstWhere(
        (String item) => _normalizeHeader(item).key == descriptor.key,
      );
      final values = columns[key]!;
      const batchSize = 10;

      for (var offset = 0; offset < values.length; offset += batchSize) {
        final end = offset + batchSize > values.length
            ? values.length
            : offset + batchSize;
        frames.add(
          SignalFrame(
            deviceId: deviceId,
            sessionId: sessionId,
            seq: seq++,
            timestampMs: timestamps[offset],
            channelKey: descriptor.key,
            sampleRate: descriptor.sampleRate,
            unit: descriptor.unit,
            quality: 0.92,
            samples: values.sublist(offset, end),
          ),
        );
      }
    }

    frames.sort(
      (SignalFrame a, SignalFrame b) => a.timestampMs.compareTo(b.timestampMs),
    );
    return frames;
  }

  List<String> _splitCsvLine(String line) {
    return line.split(',').map((String item) => item.trim()).toList();
  }

  _NormalizedChannel _normalizeHeader(String header) {
    final segments =
        header.split('_').where((String part) => part.isNotEmpty).toList();
    if (segments.isEmpty) {
      return const _NormalizedChannel(
        key: 'channel',
        label: 'CHANNEL',
        unit: 'a.u.',
      );
    }
    final unit = segments.length > 1 ? segments.last : 'a.u.';
    final key = segments.first.toLowerCase();
    final label = segments.first.toUpperCase();
    return _NormalizedChannel(key: key, label: label, unit: unit);
  }

  void _emitStatus(AdapterState state, String message) {
    _statusController.add(
      AdapterStatus(
        state: state,
        message: message,
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _frameController.close();
    _statusController.close();
    _catalogController.close();
  }
}

class BluetoothDataSourceAdapter implements DataSourceAdapter {
  BluetoothDataSourceAdapter(this.config);

  final BluetoothAdapterConfig config;
  final StreamController<SignalFrame> _frameController =
      StreamController<SignalFrame>.broadcast();
  final StreamController<AdapterStatus> _statusController =
      StreamController<AdapterStatus>.broadcast();
  final StreamController<List<ChannelDescriptor>> _catalogController =
      StreamController<List<ChannelDescriptor>>.broadcast();

  dynamic _device;
  dynamic _server;
  dynamic _service;
  dynamic _notifyCharacteristic;
  dynamic _controlCharacteristic;
  dynamic _notificationCallback;
  dynamic _disconnectCallback;
  final List<int> _receiveBuffer = <int>[];
  List<ChannelDescriptor> _currentCatalog = const <ChannelDescriptor>[];
  String _deviceId = 'esp32-bio';
  String _sessionId = 'ble-session';

  @override
  Stream<SignalFrame> get streamFrames => _frameController.stream;

  @override
  Stream<AdapterStatus> get streamStatus => _statusController.stream;

  @override
  Stream<List<ChannelDescriptor>> get streamCatalog => _catalogController.stream;

  @override
  Future<void> connect() async {
    await disconnect();
    _emitStatus(AdapterState.connecting, '正在请求蓝牙设备访问权限...');

    final bluetooth = js_util.getProperty(html.window.navigator, 'bluetooth');
    if (bluetooth == null) {
      _emitStatus(AdapterState.error, '当前浏览器不支持 Web Bluetooth');
      throw Exception('Web Bluetooth is not available.');
    }

    final options = _buildRequestOptions();
    try {
      _device = await js_util.promiseToFuture<dynamic>(
        js_util.callMethod(bluetooth, 'requestDevice', <dynamic>[options]),
      );

      _disconnectCallback = js_util.allowInterop((dynamic _) {
        _emitStatus(AdapterState.disconnected, '蓝牙设备已断开');
      });
      js_util.callMethod(
        _device,
        'addEventListener',
        <dynamic>['gattserverdisconnected', _disconnectCallback],
      );

      final gatt = js_util.getProperty(_device, 'gatt');
      _server = await js_util.promiseToFuture<dynamic>(
        js_util.callMethod(gatt, 'connect', const <dynamic>[]),
      );
      _service = await js_util.promiseToFuture<dynamic>(
        js_util.callMethod(
          _server,
          'getPrimaryService',
          <dynamic>[config.serviceUuid],
        ),
      );
      _notifyCharacteristic = await js_util.promiseToFuture<dynamic>(
        js_util.callMethod(
          _service,
          'getCharacteristic',
          <dynamic>[config.notifyCharacteristicUuid],
        ),
      );
      _controlCharacteristic = await js_util.promiseToFuture<dynamic>(
        js_util.callMethod(
          _service,
          'getCharacteristic',
          <dynamic>[config.controlCharacteristicUuid],
        ),
      );
      await js_util.promiseToFuture<dynamic>(
        js_util.callMethod(
          _notifyCharacteristic,
          'startNotifications',
          const <dynamic>[],
        ),
      );

      _notificationCallback = js_util.allowInterop((dynamic event) {
        _handleNotification(event);
      });
      js_util.callMethod(
        _notifyCharacteristic,
        'addEventListener',
        <dynamic>['characteristicvaluechanged', _notificationCallback],
      );

      _receiveBuffer.clear();
      _currentCatalog = const <ChannelDescriptor>[];
      final deviceName =
          (js_util.getProperty(_device, 'name') ?? config.deviceNamePrefix)
              .toString()
              .trim();
      _deviceId = deviceName.isEmpty ? config.deviceNamePrefix : deviceName;
      _sessionId = 'ble-${DateTime.now().millisecondsSinceEpoch}';
      _emitStatus(AdapterState.streaming, '蓝牙已连接: $_deviceId，等待 BIO1 二进制数据...');
    } catch (error) {
      _emitStatus(AdapterState.error, '蓝牙连接失败: $error');
      rethrow;
    }
  }

  dynamic _buildRequestOptions() {
    final prefix = config.deviceNamePrefix.trim();
    final options = <String, dynamic>{
      'optionalServices': <String>[config.serviceUuid],
    };
    if (prefix.isNotEmpty) {
      options['filters'] = <Map<String, dynamic>>[
        <String, dynamic>{
          'namePrefix': prefix,
          'services': <String>[config.serviceUuid],
        },
      ];
    } else {
      options['acceptAllDevices'] = true;
    }
    return js_util.jsify(options);
  }

  void _handleNotification(dynamic event) {
    final target = js_util.getProperty(event, 'target');
    final value = js_util.getProperty(target, 'value');
    final length = (js_util.getProperty(value, 'byteLength') as num?)?.toInt() ?? 0;
    final bytes = Uint8List(length);
    for (var index = 0; index < length; index++) {
      bytes[index] = (js_util.callMethod(value, 'getUint8', <dynamic>[index]) as num).toInt();
    }
    _receiveBuffer.addAll(bytes);
    _drainReceiveBuffer();
  }

  void _drainReceiveBuffer() {
    while (_receiveBuffer.isNotEmpty) {
      while (_receiveBuffer.isNotEmpty &&
          (_receiveBuffer.first == 0x0A || _receiveBuffer.first == 0x0D)) {
        _receiveBuffer.removeAt(0);
      }
      if (_receiveBuffer.isEmpty) {
        return;
      }
      if (_receiveBuffer.first == 0x7B) {
        if (!_tryConsumeJsonLine()) {
          return;
        }
        continue;
      }
      if (!_tryConsumeBinaryFrame()) {
        return;
      }
    }
  }

  bool _tryConsumeJsonLine() {
    final newlineIndex = _receiveBuffer.indexOf(0x0A);
    if (newlineIndex < 0) {
      return false;
    }
    final lineBytes = _receiveBuffer.sublist(0, newlineIndex);
    _receiveBuffer.removeRange(0, newlineIndex + 1);
    final line = utf8.decode(lineBytes, allowMalformed: true).trim();
    if (line.isNotEmpty) {
      _handleBleLine(line);
    }
    return true;
  }

  bool _tryConsumeBinaryFrame() {
    final magicIndex = _indexOfMagic(_receiveBuffer);
    if (magicIndex < 0) {
      if (_receiveBuffer.length > 3) {
        _receiveBuffer.removeRange(0, _receiveBuffer.length - 3);
      }
      return false;
    }
    if (magicIndex > 0) {
      _receiveBuffer.removeRange(0, magicIndex);
    }
    if (_receiveBuffer.length < 11) {
      return false;
    }

    final typeByte = _receiveBuffer[4];
    final sampleSize = _sampleSizeForType(typeByte);
    if (sampleSize == null) {
      _receiveBuffer.removeAt(0);
      return true;
    }

    final header = ByteData.sublistView(Uint8List.fromList(_receiveBuffer.sublist(0, 11)));
    final sampleCount = header.getUint16(9, Endian.little);
    final frameLength = 11 + sampleCount * sampleSize;
    if (_receiveBuffer.length < frameLength) {
      return false;
    }

    final frameBytes = Uint8List.fromList(_receiveBuffer.sublist(0, frameLength));
    _receiveBuffer.removeRange(0, frameLength);
    _handleBinaryFrame(frameBytes);
    return true;
  }

  void _handleBleLine(String line) {
    dynamic decoded;
    try {
      decoded = jsonDecode(line);
    } catch (_) {
      return;
    }
    if (decoded is! Map<String, dynamic>) {
      return;
    }

    final type = (decoded['type'] ?? '').toString();
    final payload = decoded['payload'];
    if (type == 'catalog' && payload is Map<String, dynamic>) {
      final rawChannels = (payload['channels'] as List<dynamic>? ?? const <dynamic>[]);
      _currentCatalog = rawChannels
          .map(
            (dynamic item) => ChannelDescriptor.fromJson(item as Map<String, dynamic>),
          )
          .toList();
      _catalogController.add(List<ChannelDescriptor>.from(_currentCatalog));
      _emitStatus(AdapterState.streaming, '蓝牙目录已同步，共 ${_currentCatalog.length} 个通道');
      return;
    }

    if (type == 'frame' && payload is Map<String, dynamic>) {
      _frameController.add(SignalFrame.fromJson(payload));
      return;
    }

    if (type == 'status' && payload is Map<String, dynamic>) {
      final message = (payload['message'] ?? '蓝牙状态更新').toString();
      _emitStatus(AdapterState.streaming, message);
      return;
    }

    if (type == 'alerts' && payload is Map<String, dynamic>) {
      final message = (payload['message'] ?? '蓝牙报警').toString();
      _emitStatus(AdapterState.error, message);
      return;
    }

    if (decoded.containsKey('channelKey')) {
      _frameController.add(SignalFrame.fromJson(decoded));
    }
  }

  void _handleBinaryFrame(Uint8List frameBytes) {
    final data = ByteData.sublistView(frameBytes);
    final typeCode = String.fromCharCode(frameBytes[4]);
    final seq = data.getUint32(5, Endian.little);
    final sampleCount = data.getUint16(9, Endian.little);
    final sampleSize = _sampleSizeForType(frameBytes[4]);
    if (sampleSize == null || sampleCount == 0) {
      return;
    }

    switch (typeCode) {
      case 'E':
        _handleBinaryEcgFrame(data, seq, sampleCount, sampleSize);
        return;
      case 'P':
        _handleBinaryPpgFrame(data, seq, sampleCount, sampleSize);
        return;
      case 'I':
        _handleBinaryImuFrame(data, seq, sampleCount, sampleSize);
        return;
      default:
        return;
    }
  }

  void _handleBinaryEcgFrame(
    ByteData data,
    int seq,
    int sampleCount,
    int sampleSize,
  ) {
    final timestampsUs = <int>[];
    final values = <double>[];
    for (var index = 0; index < sampleCount; index++) {
      final offset = 11 + index * sampleSize;
      timestampsUs.add(_readUint64Le(data, offset));
      values.add(data.getUint16(offset + 8, Endian.little).toDouble());
    }

    final sampleRate = _estimateSampleRate(timestampsUs, 500);
    _mergeCatalog(<ChannelDescriptor>[
      _buildChannelDescriptor(
        key: 'ecg',
        label: 'ECG',
        unit: 'adc',
        colorHex: '#F25F5C',
        sampleRate: sampleRate,
      ),
    ]);
    _emitSignalFrame(
      channelKey: 'ecg',
      seq: seq,
      unit: 'adc',
      sampleRate: sampleRate,
      timestampUs: timestampsUs.first,
      samples: values,
    );
  }

  void _handleBinaryPpgFrame(
    ByteData data,
    int seq,
    int sampleCount,
    int sampleSize,
  ) {
    final timestampsUs = <int>[];
    final irValues = <double>[];
    final redValues = <double>[];
    for (var index = 0; index < sampleCount; index++) {
      final offset = 11 + index * sampleSize;
      timestampsUs.add(_readUint64Le(data, offset));
      irValues.add(data.getUint32(offset + 8, Endian.little).toDouble());
      redValues.add(data.getUint32(offset + 12, Endian.little).toDouble());
    }

    final sampleRate = _estimateSampleRate(timestampsUs, 100);
    _mergeCatalog(<ChannelDescriptor>[
      _buildChannelDescriptor(
        key: 'ppg_ir',
        label: 'PPG IR',
        unit: 'count',
        colorHex: '#247BA0',
        sampleRate: sampleRate,
      ),
      _buildChannelDescriptor(
        key: 'ppg_red',
        label: 'PPG RED',
        unit: 'count',
        colorHex: '#C84C5A',
        sampleRate: sampleRate,
      ),
    ]);
    _emitSignalFrame(
      channelKey: 'ppg_ir',
      seq: seq,
      unit: 'count',
      sampleRate: sampleRate,
      timestampUs: timestampsUs.first,
      samples: irValues,
    );
    _emitSignalFrame(
      channelKey: 'ppg_red',
      seq: seq,
      unit: 'count',
      sampleRate: sampleRate,
      timestampUs: timestampsUs.first,
      samples: redValues,
    );
  }

  void _handleBinaryImuFrame(
    ByteData data,
    int seq,
    int sampleCount,
    int sampleSize,
  ) {
    final timestampsUs = <int>[];
    final channelSamples = <String, List<double>>{
      'imu_ax': <double>[],
      'imu_ay': <double>[],
      'imu_az': <double>[],
      'imu_gx': <double>[],
      'imu_gy': <double>[],
      'imu_gz': <double>[],
    };
    for (var index = 0; index < sampleCount; index++) {
      final offset = 11 + index * sampleSize;
      timestampsUs.add(_readUint64Le(data, offset));
      channelSamples['imu_ax']!.add(data.getInt16(offset + 8, Endian.little).toDouble());
      channelSamples['imu_ay']!.add(data.getInt16(offset + 10, Endian.little).toDouble());
      channelSamples['imu_az']!.add(data.getInt16(offset + 12, Endian.little).toDouble());
      channelSamples['imu_gx']!.add(data.getInt16(offset + 14, Endian.little).toDouble());
      channelSamples['imu_gy']!.add(data.getInt16(offset + 16, Endian.little).toDouble());
      channelSamples['imu_gz']!.add(data.getInt16(offset + 18, Endian.little).toDouble());
    }

    final sampleRate = _estimateSampleRate(timestampsUs, 100);
    _mergeCatalog(<ChannelDescriptor>[
      _buildChannelDescriptor(
        key: 'imu_ax',
        label: 'IMU AX',
        unit: 'raw',
        colorHex: '#2A9D8F',
        sampleRate: sampleRate,
      ),
      _buildChannelDescriptor(
        key: 'imu_ay',
        label: 'IMU AY',
        unit: 'raw',
        colorHex: '#36B7A1',
        sampleRate: sampleRate,
      ),
      _buildChannelDescriptor(
        key: 'imu_az',
        label: 'IMU AZ',
        unit: 'raw',
        colorHex: '#55C7AE',
        sampleRate: sampleRate,
      ),
      _buildChannelDescriptor(
        key: 'imu_gx',
        label: 'IMU GX',
        unit: 'raw',
        colorHex: '#7B6DFF',
        sampleRate: sampleRate,
      ),
      _buildChannelDescriptor(
        key: 'imu_gy',
        label: 'IMU GY',
        unit: 'raw',
        colorHex: '#9A7CFF',
        sampleRate: sampleRate,
      ),
      _buildChannelDescriptor(
        key: 'imu_gz',
        label: 'IMU GZ',
        unit: 'raw',
        colorHex: '#B792FF',
        sampleRate: sampleRate,
      ),
    ]);
    for (final entry in channelSamples.entries) {
      _emitSignalFrame(
        channelKey: entry.key,
        seq: seq,
        unit: 'raw',
        sampleRate: sampleRate,
        timestampUs: timestampsUs.first,
        samples: entry.value,
      );
    }
  }

  void _emitSignalFrame({
    required String channelKey,
    required int seq,
    required String unit,
    required double sampleRate,
    required int timestampUs,
    required List<double> samples,
  }) {
    _frameController.add(
      SignalFrame(
        deviceId: _deviceId,
        sessionId: _sessionId,
        seq: seq,
        timestampMs: timestampUs ~/ 1000,
        channelKey: channelKey,
        sampleRate: sampleRate,
        unit: unit,
        quality: 1.0,
        samples: samples,
      ),
    );
  }

  void _mergeCatalog(List<ChannelDescriptor> incoming) {
    var changed = false;
    final nextCatalog = List<ChannelDescriptor>.from(_currentCatalog);
    for (final descriptor in incoming) {
      final index = nextCatalog.indexWhere((ChannelDescriptor item) => item.key == descriptor.key);
      if (index < 0) {
        nextCatalog.add(descriptor);
        changed = true;
        continue;
      }
      final existing = nextCatalog[index];
      final updated = existing.copyWith(
        label: descriptor.label,
        unit: descriptor.unit,
        sampleRate: descriptor.sampleRate > 0 ? descriptor.sampleRate : existing.sampleRate,
        colorHex: descriptor.colorHex,
      );
      if (updated.label != existing.label ||
          updated.unit != existing.unit ||
          updated.sampleRate != existing.sampleRate ||
          updated.colorHex != existing.colorHex) {
        nextCatalog[index] = updated;
        changed = true;
      }
    }
    if (!changed) {
      return;
    }
    _currentCatalog = nextCatalog;
    _catalogController.add(List<ChannelDescriptor>.from(_currentCatalog));
    _emitStatus(AdapterState.streaming, '已识别 ${_currentCatalog.length} 个蓝牙二进制通道');
  }

  ChannelDescriptor _buildChannelDescriptor({
    required String key,
    required String label,
    required String unit,
    required String colorHex,
    required double sampleRate,
  }) {
    final existingIndex =
        _currentCatalog.indexWhere((ChannelDescriptor item) => item.key == key);
    final existing = existingIndex >= 0 ? _currentCatalog[existingIndex] : null;
    return ChannelDescriptor(
      key: key,
      label: label,
      unit: unit,
      sampleRate: sampleRate,
      colorHex: colorHex,
      enabled: existing?.enabled ?? true,
    );
  }

  int? _sampleSizeForType(int typeByte) {
    switch (String.fromCharCode(typeByte)) {
      case 'E':
        return 12;
      case 'P':
        return 16;
      case 'I':
        return 20;
      default:
        return null;
    }
  }

  int _indexOfMagic(List<int> buffer) {
    for (var index = 0; index <= buffer.length - 4; index++) {
      if (buffer[index] == 0x42 &&
          buffer[index + 1] == 0x49 &&
          buffer[index + 2] == 0x4F &&
          buffer[index + 3] == 0x31) {
        return index;
      }
    }
    return -1;
  }

  int _readUint64Le(ByteData data, int offset) {
    final low = data.getUint32(offset, Endian.little);
    final high = data.getUint32(offset + 4, Endian.little);
    return high * 0x100000000 + low;
  }

  double _estimateSampleRate(List<int> timestampsUs, double fallback) {
    if (timestampsUs.length < 2) {
      return fallback;
    }
    var totalDelta = 0;
    var count = 0;
    for (var index = 1; index < timestampsUs.length; index++) {
      final delta = timestampsUs[index] - timestampsUs[index - 1];
      if (delta > 0) {
        totalDelta += delta;
        count++;
      }
    }
    if (count == 0 || totalDelta <= 0) {
      return fallback;
    }
    return 1000000.0 / (totalDelta / count);
  }

  @override
  Future<void> disconnect() async {
    try {
      if (_notifyCharacteristic != null && _notificationCallback != null) {
        js_util.callMethod(
          _notifyCharacteristic,
          'removeEventListener',
          <dynamic>['characteristicvaluechanged', _notificationCallback],
        );
        await js_util.promiseToFuture<dynamic>(
          js_util.callMethod(
            _notifyCharacteristic,
            'stopNotifications',
            const <dynamic>[],
          ),
        );
      }
    } catch (_) {}

    try {
      if (_device != null && _disconnectCallback != null) {
        js_util.callMethod(
          _device,
          'removeEventListener',
          <dynamic>['gattserverdisconnected', _disconnectCallback],
        );
      }
    } catch (_) {}

    try {
      if (_server != null) {
        js_util.callMethod(_server, 'disconnect', const <dynamic>[]);
      }
    } catch (_) {
      try {
        final gatt = js_util.getProperty(_device, 'gatt');
        js_util.callMethod(gatt, 'disconnect', const <dynamic>[]);
      } catch (_) {}
    }

    _device = null;
    _server = null;
    _service = null;
    _notifyCharacteristic = null;
    _controlCharacteristic = null;
    _notificationCallback = null;
    _disconnectCallback = null;
    _receiveBuffer.clear();
    _currentCatalog = const <ChannelDescriptor>[];
    _deviceId = config.deviceNamePrefix;
    _sessionId = 'ble-session';
    _emitStatus(AdapterState.disconnected, '蓝牙连接已关闭');
  }

  @override
  Future<void> updateChannels(List<ChannelDescriptor> channels) async {
    _currentCatalog = List<ChannelDescriptor>.from(channels);
    await sendControl(
      ControlCommand(
        type: 'set_channels',
        payload: <String, dynamic>{
          'enabledKeys': channels
              .where((ChannelDescriptor item) => item.enabled)
              .map((ChannelDescriptor item) => item.key)
              .toList(),
        },
      ),
    );
  }

  @override
  Future<void> sendControl(ControlCommand command) async {
    final characteristic = _controlCharacteristic;
    if (characteristic == null) {
      return;
    }

    final bytes = Uint8List.fromList(utf8.encode('${jsonEncode(command.toJson())}\n'));
    try {
      if (js_util.hasProperty(characteristic, 'writeValueWithoutResponse')) {
        await js_util.promiseToFuture<dynamic>(
          js_util.callMethod(
            characteristic,
            'writeValueWithoutResponse',
            <dynamic>[bytes],
          ),
        );
      } else {
        await js_util.promiseToFuture<dynamic>(
          js_util.callMethod(characteristic, 'writeValue', <dynamic>[bytes]),
        );
      }
    } catch (error) {
      _emitStatus(AdapterState.error, '蓝牙写入失败: $error');
      rethrow;
    }
  }

  void _emitStatus(AdapterState state, String message) {
    _statusController.add(
      AdapterStatus(
        state: state,
        message: message,
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  void dispose() {
    _frameController.close();
    _statusController.close();
    _catalogController.close();
  }
}

class _NormalizedChannel {
  const _NormalizedChannel({
    required this.key,
    required this.label,
    required this.unit,
  });

  final String key;
  final String label;
  final String unit;
}


