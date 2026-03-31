import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'models.dart';
import 'monitor_controller.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late final MonitorController _controller;
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _pathController;
  late final TextEditingController _deviceIdController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _cloudController;
  late final TextEditingController _bleNamePrefixController;
  late final TextEditingController _bleServiceController;
  late final TextEditingController _bleNotifyController;
  late final TextEditingController _bleControlController;

  int _sidePanelIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = MonitorController();
    _hostController = TextEditingController(text: _controller.mqttConfig.host);
    _portController = TextEditingController(text: _controller.mqttConfig.port.toString());
    _pathController = TextEditingController(text: _controller.mqttConfig.path);
    _deviceIdController = TextEditingController(text: _controller.mqttConfig.deviceId);
    _usernameController = TextEditingController(text: _controller.mqttConfig.username);
    _passwordController = TextEditingController(text: _controller.mqttConfig.password);
    _cloudController = TextEditingController(text: _controller.cloudBaseUrl);
    _bleNamePrefixController = TextEditingController(text: _controller.bluetoothConfig.deviceNamePrefix);
    _bleServiceController = TextEditingController(text: _controller.bluetoothConfig.serviceUuid);
    _bleNotifyController = TextEditingController(text: _controller.bluetoothConfig.notifyCharacteristicUuid);
    _bleControlController = TextEditingController(text: _controller.bluetoothConfig.controlCharacteristicUuid);
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _pathController.dispose();
    _deviceIdController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _cloudController.dispose();
    _bleNamePrefixController.dispose();
    _bleServiceController.dispose();
    _bleNotifyController.dispose();
    _bleControlController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('多源心肺功能监测上位机'),
            actions: <Widget>[
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(child: _StatusBadge(status: _controller.status)),
              ),
            ],
          ),
          body: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final isCompact = constraints.maxWidth < 1180;
              final content = <Widget>[
                SizedBox(
                  width: isCompact ? double.infinity : 400,
                  child: _buildControlPanel(context),
                ),
                SizedBox(width: isCompact ? 0 : 20, height: isCompact ? 20 : 0),
                Expanded(child: _buildWaveformArea(context)),
              ];

              return Padding(
                padding: const EdgeInsets.all(20),
                child: isCompact
                    ? Column(children: content)
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: content,
                      ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildControlPanel(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('功能分区', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('配置与记录'),
                          selected: _sidePanelIndex == 0,
                          onSelected: (_) => setState(() => _sidePanelIndex = 0),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('控制与分析'),
                          selected: _sidePanelIndex == 1,
                          onSelected: (_) => setState(() => _sidePanelIndex = 1),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _sidePanelIndex == 0
                        ? '用于切换数据源、配置连接参数和查看运行日志。'
                        : '用于控制波形显示，并查看本地统计与云端分析结果。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_sidePanelIndex == 0) ...<Widget>[
            _buildDataSourceCard(context),
            const SizedBox(height: 16),
            _buildStatusLogCard(context),
          ] else ...<Widget>[
            _buildDisplayControlCard(context),
            const SizedBox(height: 16),
            _buildChannelCatalogCard(context),
            const SizedBox(height: 16),
            _buildLocalAnalysisCard(context),
            const SizedBox(height: 16),
            _buildCloudAnalysisCard(context),
          ],
        ],
      ),
    );
  }

  Widget _buildDataSourceCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('数据源', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: DataSourceMode.values.map((DataSourceMode item) {
                return ChoiceChip(
                  label: Text(item.label),
                  selected: _controller.mode == item,
                  onSelected: (_) => _controller.setMode(item),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            if (_controller.mode == DataSourceMode.wifi) ...<Widget>[
              _buildTextField('Broker Host', _hostController, (String value) {
                _controller.updateMqttConfig(host: value);
              }),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _buildTextField('端口', _portController, (String value) {
                      final parsed = int.tryParse(value);
                      if (parsed != null) {
                        _controller.updateMqttConfig(port: parsed);
                      }
                    }),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildTextField('WebSocket Path', _pathController, (String value) {
                      _controller.updateMqttConfig(path: value);
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildTextField('设备 ID', _deviceIdController, (String value) {
                _controller.updateMqttConfig(deviceId: value);
              }),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _buildTextField('用户名', _usernameController, (String value) {
                      _controller.updateMqttConfig(username: value);
                    }),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildTextField('密码', _passwordController, (String value) {
                      _controller.updateMqttConfig(password: value);
                    }, obscureText: true),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用 TLS / WSS'),
                value: _controller.mqttConfig.useTls,
                onChanged: (bool value) => _controller.updateMqttConfig(useTls: value),
              ),
            ],
            if (_controller.mode == DataSourceMode.file) ...<Widget>[
              FilledButton.tonalIcon(
                onPressed: _controller.pickReplayFile,
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('选择 CSV / JSON'),
              ),
              const SizedBox(height: 10),
              Text(_controller.hasReplayFile ? '当前文件: ${_controller.replayFileName}' : '未选择回放文件'),
              const SizedBox(height: 8),
              const Text('建议先用仓库里的长样例 CSV 验证滚动、暂停和回滚功能。'),
            ],
            if (_controller.mode == DataSourceMode.bluetooth) ...<Widget>[
              _buildTextField('设备名前缀', _bleNamePrefixController, (String value) {
                _controller.updateBluetoothConfig(deviceNamePrefix: value);
              }),
              const SizedBox(height: 12),
              _buildTextField('服务 UUID', _bleServiceController, (String value) {
                _controller.updateBluetoothConfig(serviceUuid: value);
              }),
              const SizedBox(height: 12),
              _buildTextField('通知特征 UUID', _bleNotifyController, (String value) {
                _controller.updateBluetoothConfig(notifyCharacteristicUuid: value);
              }),
              const SizedBox(height: 12),
              _buildTextField('控制特征 UUID', _bleControlController, (String value) {
                _controller.updateBluetoothConfig(controlCharacteristicUuid: value);
              }),
              const SizedBox(height: 8),
              const Text('蓝牙模式基于 Web Bluetooth，只能在 Chrome / Edge 的 HTTPS 或 localhost 环境下使用。'),
            ],
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _controller.isConnected ? _controller.disconnect : _controller.connect,
                    icon: Icon(_controller.isConnected ? Icons.stop_circle_outlined : Icons.play_arrow),
                    label: Text(_controller.isConnected ? '断开 / 停止' : '连接 / 开始'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  Widget _buildDisplayControlCard(BuildContext context) {
    final maxOffset = _controller.maxHistoryOffsetSeconds;
    final historySliderMax = maxOffset <= 0 ? 1.0 : maxOffset;
    final historySliderValue = _controller.isPaused
        ? _controller.historyOffsetSeconds.clamp(0.0, historySliderMax)
        : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('显示控制', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _controller.togglePause,
                    icon: Icon(_controller.isPaused ? Icons.play_arrow : Icons.pause),
                    label: Text(_controller.isPaused ? '继续播放' : '暂停回看'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _controller.isPaused
                  ? '当前已暂停，历史回滚已解锁；点击继续播放会自动回到最新位置。'
                  : '当前处于实时播放状态，历史回滚锁定并自动跟随最新数据。',
            ),
            const SizedBox(height: 16),
            Text('时间窗: ${_controller.secondsPerScreen.toStringAsFixed(1)} s'),
            Slider(
              value: _controller.secondsPerScreen,
              min: 2,
              max: 20,
              divisions: 18,
              onChanged: _controller.setSecondsPerScreen,
            ),
            Text(_controller.isPaused ? '历史回滚: ${historySliderValue.toStringAsFixed(1)} s' : '历史回滚: 实时锁定'),
            Slider(
              value: historySliderValue,
              min: 0,
              max: historySliderMax,
              onChanged: _controller.canRollbackHistory ? _controller.setHistoryOffsetSeconds : null,
            ),
            if (_controller.isPaused && !_controller.canRollbackHistory)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('当前缓存长度不足一个完整时间窗，已补长样例 CSV 供调试使用。'),
              ),
            Text('增益: ${_controller.gain.toStringAsFixed(1)} x'),
            Slider(
              value: _controller.gain,
              min: 0.5,
              max: 4,
              divisions: 14,
              onChanged: _controller.setGain,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelCatalogCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('通道显隐', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (_controller.channelCatalog.isEmpty)
              const Text('当前尚未收到通道目录，可以先导入文件或连接 ESP32。'),
            for (final ChannelDescriptor channel in _controller.channelCatalog)
              SwitchListTile.adaptive(
                value: channel.enabled,
                contentPadding: EdgeInsets.zero,
                title: Text('${channel.label} (${channel.unit})'),
                subtitle: Text('${channel.sampleRate.toStringAsFixed(1)} Hz'),
                secondary: CircleAvatar(
                  radius: 8,
                  backgroundColor: colorFromHex(channel.colorHex),
                ),
                onChanged: (bool value) => _controller.toggleChannel(channel.key, value),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalAnalysisCard(BuildContext context) {
    final analysis = _controller.localAnalysis;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('本地统计与分析', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('这里先放轻量统计与简单规则分析，后续可以继续接本地模型或信号处理模块。'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _MetricChip(label: '启用通道', value: '${analysis.activeChannels}'),
                _MetricChip(label: '最长时长', value: '${analysis.durationSeconds.toStringAsFixed(1)} s'),
                _MetricChip(label: '平均质量', value: '${(analysis.meanQuality * 100).toStringAsFixed(0)} %'),
              ],
            ),
            const SizedBox(height: 16),
            Text('即时结论', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (analysis.findings.isEmpty) const Text('暂无本地分析结论'),
            ...analysis.findings.map(
              (String item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _FindingTile(text: item),
              ),
            ),
            const SizedBox(height: 12),
            Text('通道统计', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (analysis.channels.isEmpty) const Text('暂无可统计的通道数据'),
            ...analysis.channels.map(
              (LocalChannelAnalysis item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFDCE3EA)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Text('${item.label} (${item.unit})', style: Theme.of(context).textTheme.titleSmall),
                          const Spacer(),
                          if (item.estimatedRateBpm != null)
                            Text('${item.estimatedRateBpm!.toStringAsFixed(1)} BPM'),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          _MetricChip(label: '样本', value: '${item.sampleCount}'),
                          _MetricChip(label: '均值', value: item.mean.toStringAsFixed(3)),
                          _MetricChip(label: '峰峰值', value: item.peakToPeak.toStringAsFixed(3)),
                          _MetricChip(label: 'RMS', value: item.rms.toStringAsFixed(3)),
                          _MetricChip(label: '标准差', value: item.stdDev.toStringAsFixed(3)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text('范围 ${item.min.toStringAsFixed(3)} ~ ${item.max.toStringAsFixed(3)}，时长 ${item.durationSeconds.toStringAsFixed(1)} s，质量 ${(item.meanQuality * 100).toStringAsFixed(0)} %'),
                      if (item.notes.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 8),
                        Text(item.notes.join(' · ')),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCloudAnalysisCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('云端分析', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _buildTextField('云端地址', _cloudController, (String value) {
              _controller.updateCloudBaseUrl(value);
            }),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _controller.uploadAndAnalyze,
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: const Text('上传并分析'),
                  ),
                ),
              ],
            ),
            if (_controller.uploadTask != null) ...<Widget>[
              const SizedBox(height: 12),
              Text('上传任务: ${_controller.uploadTask!.id}'),
              Text('状态: ${_controller.uploadTask!.status}'),
            ],
            if (_controller.analysisJob != null) ...<Widget>[
              const SizedBox(height: 12),
              Text('分析任务: ${_controller.analysisJob!.id}'),
              Text('状态: ${_controller.analysisJob!.status}'),
              if (_controller.analysisJob!.summary.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_controller.analysisJob!.summary),
                ),
            ],
            if (_controller.report != null) ...<Widget>[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFDCE3EA)),
                ),
                child: Text(_controller.report!.summary),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusLogCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('状态日志', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (_controller.events.isEmpty) const Text('尚无日志'),
            ..._controller.events.take(14).map(
              (String item) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(item),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaveformArea(BuildContext context) {
    return Column(
      children: <Widget>[
        Card(
          child: ListTile(
            title: Text(_controller.session == null ? '等待开始监测' : '会话 ${_controller.session!.id}'),
            subtitle: Text(
              _controller.session == null
                  ? '请先连接 MQTT / 蓝牙设备，或导入回放文件。'
                  : '设备 ${_controller.session!.deviceId} | 模式 ${_controller.session!.sourceMode} | 通道 ${_controller.session!.channelKeys.join(', ')}',
            ),
            trailing: _MetricChip(label: '锚点', value: _controller.isPaused ? '暂停回看' : '实时最新'),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _controller.visibleChannels.isEmpty
              ? Card(
                  child: Center(
                    child: Text(
                      '暂无可显示的通道\n请先导入数据文件、连接 MQTT 或连接蓝牙设备',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: _controller.visibleChannels.length + (_controller.report != null ? 1 : 0),
                  separatorBuilder: (_, __) => const SizedBox(height: 16),
                  itemBuilder: (BuildContext context, int index) {
                    if (_controller.report != null && index == _controller.visibleChannels.length) {
                      return _ReportCard(report: _controller.report!);
                    }
                    final channel = _controller.visibleChannels[index];
                    return _WaveformCard(
                      channel: channel,
                      points: _controller.visiblePoints(channel.key),
                      gain: _controller.gain,
                      secondsPerScreen: _controller.secondsPerScreen,
                      anchorTimestampMs: _controller.currentAnchorTimestampMs,
                      summary: _controller.channelSummary(channel.key),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, ValueChanged<String> onChanged, {bool obscureText = false}) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final AdapterStatus status;

  @override
  Widget build(BuildContext context) {
    Color background;
    switch (status.state) {
      case AdapterState.streaming:
        background = const Color(0xFFD7F9E9);
        break;
      case AdapterState.connected:
        background = const Color(0xFFE6F4FF);
        break;
      case AdapterState.error:
        background = const Color(0xFFFFE5E5);
        break;
      default:
        background = const Color(0xFFF1F3F5);
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(status.message),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF6FBF8),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD5E7DD)),
      ),
      child: Text('$label  $value'),
    );
  }
}

class _FindingTile extends StatelessWidget {
  const _FindingTile({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDCE3EA)),
      ),
      child: Text(text),
    );
  }
}

class _WaveformCard extends StatefulWidget {
  const _WaveformCard({
    required this.channel,
    required this.points,
    required this.gain,
    required this.secondsPerScreen,
    required this.anchorTimestampMs,
    required this.summary,
  });

  final ChannelDescriptor channel;
  final List<SamplePoint> points;
  final double gain;
  final double secondsPerScreen;
  final int anchorTimestampMs;
  final Map<String, dynamic> summary;

  @override
  State<_WaveformCard> createState() => _WaveformCardState();
}

class _WaveformCardState extends State<_WaveformCard> {
  HoverSampleInfo? _hoverInfo;

  @override
  void didUpdateWidget(covariant _WaveformCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.points.isEmpty && _hoverInfo != null) {
      _hoverInfo = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final estimatedRate = _safeNullableDouble(widget.summary['estimatedRateBpm']);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 8,
                  backgroundColor: colorFromHex(widget.channel.colorHex),
                ),
                const SizedBox(width: 10),
                Text('${widget.channel.label} (${widget.channel.unit})', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Text('${widget.channel.sampleRate.toStringAsFixed(1)} Hz'),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '样本 ${widget.summary['samples'] ?? 0} | 均值 ${_safeDouble(widget.summary['mean']).toStringAsFixed(3)} | 范围 ${_safeDouble(widget.summary['min']).toStringAsFixed(3)} ~ ${_safeDouble(widget.summary['max']).toStringAsFixed(3)}${estimatedRate == null ? '' : ' | 节律 ${estimatedRate.toStringAsFixed(1)} BPM'}',
            ),
            const SizedBox(height: 8),
            Text(
              _hoverInfo == null
                  ? '提示：鼠标移动到波形上可查看当前点位数值。'
                  : '游标值 ${_hoverInfo!.sample.value.toStringAsFixed(4)} ${widget.channel.unit} @ ${_formatTimestamp(_hoverInfo!.sample.timestampMs)}',
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 220,
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final width = constraints.maxWidth;
                  const height = 220.0;
                  return MouseRegion(
                    onExit: (_) {
                      if (_hoverInfo != null) {
                        setState(() {
                          _hoverInfo = null;
                        });
                      }
                    },
                    onHover: (event) {
                      final nextHover = _resolveHover(localPosition: event.localPosition, width: width, height: height);
                      if (_hoverEquals(_hoverInfo, nextHover)) {
                        return;
                      }
                      setState(() {
                        _hoverInfo = nextHover;
                      });
                    },
                    child: Stack(
                      children: <Widget>[
                        Positioned.fill(
                          child: CustomPaint(
                            painter: WaveformPainter(
                              points: widget.points,
                              color: colorFromHex(widget.channel.colorHex),
                              gain: widget.gain,
                              secondsPerScreen: widget.secondsPerScreen,
                              anchorTimestampMs: widget.anchorTimestampMs,
                            ),
                            child: widget.points.isEmpty
                                ? const Center(child: Text('当前窗口暂无数据'))
                                : const SizedBox.expand(),
                          ),
                        ),
                        if (_hoverInfo != null) ...<Widget>[
                          Positioned(
                            left: _hoverInfo!.localDx - 0.5,
                            top: 0,
                            bottom: 0,
                            child: Container(width: 1, color: const Color(0xFF51606B)),
                          ),
                          Positioned(
                            left: _hoverInfo!.localDx - 4,
                            top: _hoverInfo!.localDy - 4,
                            child: IgnorePointer(
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: colorFromHex(widget.channel.colorHex),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: _bubbleLeft(_hoverInfo!, width),
                            top: _bubbleTop(_hoverInfo!, height),
                            child: IgnorePointer(
                              child: Container(
                                width: 156,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF132A13),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: DefaultTextStyle(
                                  style: const TextStyle(color: Colors.white, fontSize: 11),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(_formatTimestamp(_hoverInfo!.sample.timestampMs)),
                                      const SizedBox(height: 4),
                                      Text('${_hoverInfo!.sample.value.toStringAsFixed(4)} ${widget.channel.unit}'),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  HoverSampleInfo? _resolveHover({required Offset localPosition, required double width, required double height}) {
    if (widget.points.isEmpty || width <= 0 || height <= 0) {
      return null;
    }

    final windowMs = (widget.secondsPerScreen * 1000).round();
    final startMs = widget.anchorTimestampMs - windowMs;
    final clampedDx = localPosition.dx.clamp(0.0, width);
    final targetMs = startMs + (clampedDx / width * windowMs).round();
    final sample = _nearestSample(widget.points, targetMs);
    final viewport = _WaveformViewport.fromPoints(widget.points);
    final sampleDx = ((sample.timestampMs - startMs) / windowMs).clamp(0.0, 1.0) * width;
    final sampleDy = viewport.dyForValue(value: sample.value, gain: widget.gain, height: height);

    return HoverSampleInfo(sample: sample, localDx: sampleDx, localDy: sampleDy);
  }

  SamplePoint _nearestSample(List<SamplePoint> points, int targetTimestampMs) {
    if (points.length == 1) {
      return points.first;
    }
    var low = 0;
    var high = points.length - 1;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      final current = points[mid].timestampMs;
      if (current == targetTimestampMs) {
        return points[mid];
      }
      if (current < targetTimestampMs) {
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    if (low >= points.length) {
      return points.last;
    }
    if (high < 0) {
      return points.first;
    }

    final lowPoint = points[low];
    final highPoint = points[high];
    return (lowPoint.timestampMs - targetTimestampMs).abs() < (highPoint.timestampMs - targetTimestampMs).abs() ? lowPoint : highPoint;
  }
  bool _hoverEquals(HoverSampleInfo? a, HoverSampleInfo? b) {
    if (a == null || b == null) {
      return a == b;
    }
    return a.sample.timestampMs == b.sample.timestampMs;
  }

  double _bubbleLeft(HoverSampleInfo info, double width) {
    return math.min(math.max(8, info.localDx + 12), math.max(8, width - 164));
  }

  double _bubbleTop(HoverSampleInfo info, double height) {
    final preferred = info.localDy < 72 ? info.localDy + 12 : info.localDy - 62;
    return math.min(math.max(8, preferred), math.max(8, height - 64));
  }

  String _formatTimestamp(int timestampMs) {
    final time = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    final ss = time.second.toString().padLeft(2, '0');
    final mmm = time.millisecond.toString().padLeft(3, '0');
    return '$hh:$mm:$ss.$mmm';
  }

  double _safeDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return 0;
  }

  double? _safeNullableDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return null;
  }
}

class WaveformPainter extends CustomPainter {
  WaveformPainter({
    required this.points,
    required this.color,
    required this.gain,
    required this.secondsPerScreen,
    required this.anchorTimestampMs,
  });

  final List<SamplePoint> points;
  final Color color;
  final double gain;
  final double secondsPerScreen;
  final int anchorTimestampMs;

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPaint = Paint()..color = const Color(0xFFF9FBFA);
    final gridPaint = Paint()
      ..color = const Color(0xFFD8E2DC)
      ..strokeWidth = 1;
    final midlinePaint = Paint()
      ..color = const Color(0xFFB8C7C0)
      ..strokeWidth = 1.4;
    final signalPaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(14));
    canvas.drawRRect(rrect, backgroundPaint);
    canvas.save();
    canvas.clipRRect(rrect);

    const verticalDivisions = 8;
    const horizontalDivisions = 6;
    for (var i = 0; i <= verticalDivisions; i++) {
      final dx = size.width * i / verticalDivisions;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), gridPaint);
      final secondsLeft = secondsPerScreen - secondsPerScreen * i / verticalDivisions;
      _drawLabel(canvas, size, text: '-${secondsLeft.toStringAsFixed(1)}s', offset: Offset(dx + 4, size.height - 18));
    }

    for (var j = 0; j <= horizontalDivisions; j++) {
      final dy = size.height * j / horizontalDivisions;
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), gridPaint);
    }

    if (points.length < 2) {
      canvas.restore();
      return;
    }

    final viewport = _WaveformViewport.fromPoints(points);
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), midlinePaint);
    _drawLabel(canvas, size, text: viewport.maxLabel.toStringAsFixed(2), offset: const Offset(8, 8));
    _drawLabel(canvas, size, text: viewport.minLabel.toStringAsFixed(2), offset: Offset(8, size.height - 34));

    final startMs = anchorTimestampMs - (secondsPerScreen * 1000).round();
    final path = Path();
    for (var index = 0; index < points.length; index++) {
      final point = points[index];
      final dx = ((point.timestampMs - startMs) / (secondsPerScreen * 1000)) * size.width;
      final dy = viewport.dyForValue(value: point.value, gain: gain, height: size.height);
      if (index == 0) {
        path.moveTo(dx, dy);
      } else {
        path.lineTo(dx, dy);
      }
    }
    canvas.drawPath(path, signalPaint);
    canvas.restore();
  }

  void _drawLabel(Canvas canvas, Size size, {required String text, required Offset offset}) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: const TextStyle(fontSize: 10, color: Color(0xFF51606B))),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: math.max(0, size.width - offset.dx));
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.gain != gain ||
        oldDelegate.anchorTimestampMs != anchorTimestampMs ||
        oldDelegate.secondsPerScreen != secondsPerScreen ||
        oldDelegate.color != color;
  }
}

class _WaveformViewport {
  const _WaveformViewport({required this.center, required this.halfRange});

  final double center;
  final double halfRange;

  factory _WaveformViewport.fromPoints(List<SamplePoint> points) {
    if (points.isEmpty) {
      return const _WaveformViewport(center: 0, halfRange: 1);
    }
    final minValue = points.map((SamplePoint item) => item.value).reduce(math.min);
    final maxValue = points.map((SamplePoint item) => item.value).reduce(math.max);
    final center = (minValue + maxValue) / 2;
    var halfRange = (maxValue - minValue) / 2;
    if (halfRange.abs() < 0.0001) {
      halfRange = 1;
    }
    return _WaveformViewport(center: center, halfRange: halfRange * 1.1);
  }

  double get maxLabel => center + halfRange;
  double get minLabel => center - halfRange;

  double dyForValue({required double value, required double gain, required double height}) {
    final adjusted = center + (value - center) * gain;
    final normalized = ((adjusted - center) / halfRange).clamp(-1.0, 1.0);
    return height / 2 - normalized * (height / 2);
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report});

  final MedicalReport report;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('云端报告', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('会话 ${report.sessionId}'),
            Text('生成时间 ${report.generatedAt}'),
            const SizedBox(height: 12),
            Text(report.summary),
            const SizedBox(height: 16),
            Text('主要发现', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final ReportFinding finding in report.findings)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFDCE3EA)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('${finding.title} [${finding.severity}]'),
                      const SizedBox(height: 4),
                      Text(finding.detail),
                    ],
                  ),
                ),
              ),
            Text('建议', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final String item in report.recommendations)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('• $item'),
              ),
          ],
        ),
      ),
    );
  }
}

