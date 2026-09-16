/// Local phone-number helpers.
///
/// IMPORTANT: this is a deliberately naive parser, used only to decide whether
/// two saved contacts are the *same person* before we text or call them. It is
/// NOT a canonical formatter:
///
///  * Numbers sent to the backend go as typed — the server normalises them to
///    E.164 with libphonenumber, which handles far more input shapes correctly
///    than this can (landlines, short codes, other country formats).
///  * Numbers handed to the dialer and SmsManager go as saved — Android parses
///    formatted numbers fine, and rewriting them here risks corrupting valid
///    ones (e.g. a 9-digit landline would gain a bogus country code).
library;

/// Default country calling code, applied to bare 10-digit national numbers.
const String kDefaultCountryCode = '91';

/// A best-effort comparison key for [raw], used to spot duplicate contacts.
///
/// Returns digits only, with a country code prefixed when the number is clearly
/// a bare national one. Two numbers that produce the same key are treated as
/// the same recipient:
///  * `9876543210`, `+91 98765 43210`, `098765 43210` → `919876543210`
///
/// Falls back to the trimmed input when there are no digits at all, so unusual
/// entries still compare equal to themselves rather than collapsing together.
String phoneDedupeKey(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';

  final hasPlus = trimmed.startsWith('+');
  var digits = trimmed.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return trimmed;

  // Already international — the country code is present.
  if (hasPlus) return digits;

  // "00" is the international access prefix.
  if (digits.startsWith('00')) {
    digits = digits.substring(2);
    return digits.isEmpty ? trimmed : digits;
  }

  // A national trunk prefix ("0") is not part of the subscriber number.
  if (digits.length > 10 && digits.startsWith('0')) {
    digits = digits.replaceFirst(RegExp(r'^0+'), '');
  }

  // Only a bare 10-digit number is safely assumed to be a local mobile.
  if (digits.length == 10) return '$kDefaultCountryCode$digits';
  return digits;
}

/// True when both numbers most likely reach the same person.
bool samePhone(String a, String b) => phoneDedupeKey(a) == phoneDedupeKey(b);
