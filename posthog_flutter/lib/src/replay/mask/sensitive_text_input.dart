import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

const _sensitiveAutofillHints = {
  AutofillHints.addressCity,
  AutofillHints.addressCityAndState,
  AutofillHints.addressState,
  AutofillHints.birthday,
  AutofillHints.birthdayDay,
  AutofillHints.birthdayMonth,
  AutofillHints.birthdayYear,
  AutofillHints.countryCode,
  AutofillHints.countryName,
  AutofillHints.creditCardFamilyName,
  AutofillHints.creditCardGivenName,
  AutofillHints.creditCardMiddleName,
  AutofillHints.creditCardName,
  AutofillHints.creditCardType,
  AutofillHints.email,
  AutofillHints.familyName,
  AutofillHints.fullStreetAddress,
  AutofillHints.gender,
  AutofillHints.givenName,
  AutofillHints.impp,
  AutofillHints.jobTitle,
  AutofillHints.language,
  AutofillHints.location,
  AutofillHints.middleInitial,
  AutofillHints.middleName,
  AutofillHints.name,
  AutofillHints.namePrefix,
  AutofillHints.nameSuffix,
  AutofillHints.newUsername,
  AutofillHints.nickname,
  AutofillHints.organizationName,
  AutofillHints.photo,
  AutofillHints.postalAddress,
  AutofillHints.postalAddressExtended,
  AutofillHints.postalAddressExtendedPostalCode,
  AutofillHints.postalCode,
  AutofillHints.streetAddressLevel1,
  AutofillHints.streetAddressLevel2,
  AutofillHints.streetAddressLevel3,
  AutofillHints.streetAddressLevel4,
  AutofillHints.streetAddressLine1,
  AutofillHints.streetAddressLine2,
  AutofillHints.streetAddressLine3,
  AutofillHints.sublocality,
  AutofillHints.telephoneNumber,
  AutofillHints.telephoneNumberAreaCode,
  AutofillHints.telephoneNumberCountryCode,
  AutofillHints.telephoneNumberDevice,
  AutofillHints.telephoneNumberExtension,
  AutofillHints.telephoneNumberLocal,
  AutofillHints.telephoneNumberLocalPrefix,
  AutofillHints.telephoneNumberLocalSuffix,
  AutofillHints.telephoneNumberNational,
  AutofillHints.transactionAmount,
  AutofillHints.transactionCurrency,
  AutofillHints.url,
  AutofillHints.username,
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
      const [
        TextInputType.visiblePassword,
        TextInputType.emailAddress,
        TextInputType.phone,
        TextInputType.name,
        TextInputType.streetAddress,
        TextInputType.url,
      ].contains(keyboardType) ||
      (autofillHints?.any(_sensitiveAutofillHints.contains) ?? false);
}
