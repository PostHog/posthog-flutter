import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/src/replay/mask/sensitive_text_input.dart';

void main() {
  for (final hint in [
    AutofillHints.addressCity,
    AutofillHints.addressCityAndState,
    AutofillHints.addressState,
    AutofillHints.birthday,
    AutofillHints.birthdayDay,
    AutofillHints.birthdayMonth,
    AutofillHints.birthdayYear,
    AutofillHints.countryCode,
    AutofillHints.countryName,
    AutofillHints.creditCardExpirationDate,
    AutofillHints.creditCardExpirationDay,
    AutofillHints.creditCardExpirationMonth,
    AutofillHints.creditCardExpirationYear,
    AutofillHints.creditCardFamilyName,
    AutofillHints.creditCardGivenName,
    AutofillHints.creditCardMiddleName,
    AutofillHints.creditCardName,
    AutofillHints.creditCardNumber,
    AutofillHints.creditCardSecurityCode,
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
    AutofillHints.newPassword,
    AutofillHints.newUsername,
    AutofillHints.nickname,
    AutofillHints.oneTimeCode,
    AutofillHints.organizationName,
    AutofillHints.password,
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
  ]) {
    test('protects standard autofill hint $hint on every input surface', () {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      for (final widget in [
        TextField(autofillHints: [hint]),
        CupertinoTextField(autofillHints: [hint]),
        EditableText(
            controller: controller,
            focusNode: focusNode,
            style: const TextStyle(),
            cursorColor: Colors.blue,
            backgroundCursorColor: Colors.grey,
            autofillHints: [hint]),
      ]) {
        expect(isSensitiveTextInput(widget), isTrue);
      }
    });
  }

  for (final type in [
    TextInputType.visiblePassword,
    TextInputType.emailAddress,
    TextInputType.phone,
    TextInputType.name,
    TextInputType.streetAddress,
    TextInputType.url
  ]) {
    test('protects sensitive keyboard type $type without autofill hints', () {
      expect(isSensitiveTextInput(TextField(keyboardType: type)), isTrue);
      expect(
          isSensitiveTextInput(CupertinoTextField(keyboardType: type)), isTrue);
    });
  }

  test('does not classify unannotated or unknown custom inputs as sensitive',
      () {
    for (final widget in [
      const TextField(),
      const TextField(keyboardType: TextInputType.number),
      const TextField(autofillHints: ['custom-search'])
    ]) {
      expect(isSensitiveTextInput(widget), isFalse);
    }
  });
}
