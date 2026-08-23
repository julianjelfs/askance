import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

MqttClient createClient(String url, int port, String clientId) {
  final client = MqttServerClient.withPort(url, clientId, port);
  client.useWebSocket = true;
  return client;
}
