import 'package:intl/intl.dart';

final _money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final _dateTime = DateFormat("dd/MM 'às' HH:mm", 'pt_BR');
final _date = DateFormat('dd/MM/yyyy', 'pt_BR');

String money(num v) => _money.format(v);

String dateTime(DateTime d) => _dateTime.format(d);

String date(DateTime d) => _date.format(d);

/// "agora", "há 5 min", "há 2 h", senão a data.
String ago(DateTime d, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(d);
  if (diff.inMinutes < 1) return 'agora';
  if (diff.inMinutes < 60) return 'há ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'há ${diff.inHours} h';
  return dateTime(d);
}

/// Link do WhatsApp (só números; Brasil sem DDI ganha 55).
Uri whatsappUri(String phone, [String text = '']) {
  var digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.length <= 11) digits = '55$digits';
  return Uri.parse('https://wa.me/$digits${text.isEmpty ? '' : '?text=${Uri.encodeComponent(text)}'}');
}

/// Distância para mostrar: "3 km", "2,5 km".
String kmLabel(double km) => '${km == km.roundToDouble() ? km.toInt() : km.toString().replaceAll('.', ',')} km';
