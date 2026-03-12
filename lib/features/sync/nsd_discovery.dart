import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:multicast_dns/multicast_dns.dart';

const _serviceType = '_wenwentome._tcp.local';
const _defaultSyncPort = 7755;

class DiscoveredDevice {
  const DiscoveredDevice({
    required this.name,
    required this.host,
    required this.port,
  });

  final String name;
  final String host;
  final int port;

  String get connectUrl => 'http://$host:$port';

  @override
  String toString() => '$name ($host:$port)';
}

class NsdDiscovery {
  MDnsClient? _client;
  bool _scanning = false;

  Future<List<DiscoveredDevice>> scan({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (_scanning) {
      return const <DiscoveredDevice>[];
    }
    _scanning = true;
    final discovered = <DiscoveredDevice>[];

    try {
      discovered.addAll(await _scanMdns(timeout));
      if (discovered.isEmpty) {
        discovered.addAll(await _scanLocalSubnet(timeout));
      }
    } catch (_) {
      // Ignore network or permission failures and return what we have.
    } finally {
      _client?.stop();
      _client = null;
      _scanning = false;
    }

    final seen = <String>{};
    return discovered.where((device) => seen.add(device.host)).toList();
  }

  Future<List<DiscoveredDevice>> _scanMdns(Duration timeout) async {
    final discovered = <DiscoveredDevice>[];
    _client = MDnsClient();
    await _client!.start();

    final ptrStream = _client!.lookup<PtrResourceRecord>(
      ResourceRecordQuery.serverPointer(_serviceType),
    );

    await for (final ptr in ptrStream.timeout(
      timeout,
      onTimeout: (sink) => sink.close(),
    )) {
      final srvStream = _client!.lookup<SrvResourceRecord>(
        ResourceRecordQuery.service(ptr.domainName),
      );
      await for (final srv in srvStream.timeout(
        const Duration(seconds: 2),
        onTimeout: (sink) => sink.close(),
      )) {
        final aStream = _client!.lookup<IPAddressResourceRecord>(
          ResourceRecordQuery.addressIPv4(srv.target),
        );
        await for (final ip in aStream.timeout(
          const Duration(seconds: 2),
          onTimeout: (sink) => sink.close(),
        )) {
          discovered.add(
            DiscoveredDevice(
              name: ptr.domainName
                  .replaceFirst('.$_serviceType', '')
                  .replaceFirst('.local', ''),
              host: ip.address.address,
              port: srv.port,
            ),
          );
          break;
        }
      }
    }

    return discovered;
  }

  Future<List<DiscoveredDevice>> _scanLocalSubnet(Duration timeout) async {
    final candidates = <({String host, int port})>[];
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );

    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (!_isPrivateIpv4(address)) {
          continue;
        }
        final octets = address.address.split('.');
        if (octets.length != 4) {
          continue;
        }
        final prefix = '${octets[0]}.${octets[1]}.${octets[2]}';
        for (var value = 1; value < 255; value++) {
          final host = '$prefix.$value';
          if (host == address.address) {
            continue;
          }
          candidates.add((host: host, port: _defaultSyncPort));
        }
      }
    }

    final unique = <String>{};
    final queue = candidates
        .where((candidate) => unique.add(candidate.host))
        .toList(growable: false);
    if (queue.isEmpty) {
      return const <DiscoveredDevice>[];
    }

    final deadline = DateTime.now().add(timeout);
    final results = <DiscoveredDevice>[];
    const batchSize = 24;

    for (var offset = 0; offset < queue.length; offset += batchSize) {
      if (DateTime.now().isAfter(deadline)) {
        break;
      }
      final batch = queue.skip(offset).take(batchSize).toList(growable: false);
      final found = await Future.wait(
        batch.map((candidate) => _probeHost(candidate.host, candidate.port)),
      );
      for (final device in found) {
        if (device != null) {
          results.add(device);
        }
      }
    }

    return results;
  }

  bool _isPrivateIpv4(InternetAddress address) {
    final parts = address.address.split('.');
    if (parts.length != 4) {
      return false;
    }
    final first = int.tryParse(parts[0]) ?? -1;
    final second = int.tryParse(parts[1]) ?? -1;
    if (first == 10) {
      return true;
    }
    if (first == 172 && second >= 16 && second <= 31) {
      return true;
    }
    return first == 192 && second == 168;
  }

  Future<DiscoveredDevice?> _probeHost(String host, int port) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 400);
    try {
      final request = await client
          .getUrl(Uri.parse('http://$host:$port/ping'))
          .timeout(const Duration(milliseconds: 500));
      final response = await request.close().timeout(
        const Duration(milliseconds: 700),
      );
      if (response.statusCode != 200) {
        return null;
      }

      final body = await response.transform(utf8.decoder).join();
      final payload = jsonDecode(body);
      final deviceName = payload is Map<String, dynamic>
          ? payload['device'] as String? ?? 'WenwenTome'
          : 'WenwenTome';
      return DiscoveredDevice(name: deviceName, host: host, port: port);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  void dispose() {
    _client?.stop();
    _client = null;
  }
}
