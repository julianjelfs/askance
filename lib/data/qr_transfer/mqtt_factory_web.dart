import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_browser_client.dart';

MqttClient createClient(String url, int port, String clientId) =>
    MqttBrowserClient.withPort(url, clientId, port);
