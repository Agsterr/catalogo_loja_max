import 'package:flutter/services.dart';

/// Só os dígitos de [text].
String cpfDigits(String text) => text.replaceAll(RegExp(r'\D'), '');

/// CPF válido: 11 dígitos, não todos iguais, dígitos verificadores certos.
bool cpfValid(String text) {
  final d = cpfDigits(text);
  if (d.length != 11 || RegExp(r'^(\d)\1{10}$').hasMatch(d)) return false;
  int check(int len) {
    var sum = 0;
    for (var i = 0; i < len; i++) {
      sum += int.parse(d[i]) * (len + 1 - i);
    }
    final r = (sum * 10) % 11;
    return r == 10 ? 0 : r;
  }

  return check(9) == int.parse(d[9]) && check(10) == int.parse(d[10]);
}

/// Máscara 000.000.000-00 enquanto digita.
class CpfFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final d = cpfDigits(newValue.text);
    final cut = d.length > 11 ? d.substring(0, 11) : d;
    final b = StringBuffer();
    for (var i = 0; i < cut.length; i++) {
      if (i == 3 || i == 6) b.write('.');
      if (i == 9) b.write('-');
      b.write(cut[i]);
    }
    final text = b.toString();
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}
