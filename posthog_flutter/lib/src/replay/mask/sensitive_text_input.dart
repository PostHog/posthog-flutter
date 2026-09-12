import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

const _sensitiveAutofillHints = {
  AutofillHints.password,
  AutofillHints.newPassword,
  AutofillHints.creditCardNumber,
  AutofillHints.creditCardSecurityCode,
  AutofillHints.creditCardExpirationDate,
  AutofillHints.creditCardExpirationDay,
  AutofillHints.creditCardExpirationMonth,
  AutofillHints.creditCardExpirationYear,
  AutofillHints.oneTimeCode,
};

bool isSensitiveTextInput(Widget? widget) {
  final bool obscureText;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  if (widget is EditableText) {
    obscureText = widget.obscureText;
    keyboardType = widget.keyboardType;
    autofillHints = widget.autofillHints;
  } else if (widget is TextField) {
    obscureText = widget.obscureText;
    keyboardType = widget.keyboardType;
    autofillHints = widget.autofillHints;
  } else if (widget is CupertinoTextField) {
    // Cupertino passes autofill hints through its AutofillClient, not through
    // the nested EditableText's autofillHints.
    obscureText = widget.obscureText;
    keyboardType = widget.keyboardType;
    autofillHints = widget.autofillHints;
  } else {
    return false;
  }

  return obscureText ||
      keyboardType == TextInputType.visiblePassword ||
      (autofillHints?.any(_sensitiveAutofillHints.contains) ?? false);
}
