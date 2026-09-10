import Flutter
import MessageUI
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, MFMessageComposeViewControllerDelegate {
  // Keeps the Flutter result callback alive across the async compose-sheet flow
  // (the channel call returns only once the user dismisses the sheet).
  private var pendingSmsResult: FlutterResult?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let controller = window?.rootViewController as? FlutterViewController {
      let phoneChannel = FlutterMethodChannel(
        name: "sos_emergency/phone",
        binaryMessenger: controller.binaryMessenger
      )
      phoneChannel.setMethodCallHandler { call, result in
        switch call.method {
        case "placeCall":
          guard
            let args = call.arguments as? [String: Any],
            let phoneNumber = args["phoneNumber"] as? String
          else {
            result(FlutterError(
              code: "missing_phone_number",
              message: "Phone number is empty.",
              details: nil
            ))
            return
          }

          let allowedCharacters = Set("+0123456789*#;,")
          let cleanedNumber = phoneNumber.filter { allowedCharacters.contains($0) }
          guard
            !cleanedNumber.isEmpty,
            let url = URL(string: "tel://\(cleanedNumber)")
          else {
            result(FlutterError(
              code: "invalid_phone_number",
              message: "Phone number is invalid.",
              details: nil
            ))
            return
          }

          UIApplication.shared.open(url, options: [:]) { success in
            result(success)
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }

      // iOS has no API to send SMS silently — Apple requires the user to
      // explicitly confirm the send from the system Messages compose sheet.
      // We pre-fill every emergency contact as a recipient and the location
      // message as the body, so the user only has to tap Send once. Note this
      // creates one group conversation, so recipients can see each other's
      // numbers — unlike Android, which sends a separate SMS to each contact.
      let smsChannel = FlutterMethodChannel(
        name: "sos_emergency/sms",
        binaryMessenger: controller.binaryMessenger
      )
      smsChannel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else { return }
        switch call.method {
        case "sendSms":
          guard
            let args = call.arguments as? [String: Any],
            let numbers = args["numbers"] as? [String],
            let message = args["message"] as? String,
            !numbers.isEmpty,
            !message.isEmpty
          else {
            result(FlutterError(code: "missing_args", message: "numbers/message empty.", details: nil))
            return
          }

          guard MFMessageComposeViewController.canSendText() else {
            result(FlutterError(code: "sms_unsupported", message: "This device cannot send SMS.", details: nil))
            return
          }
          guard self.pendingSmsResult == nil else {
            result(FlutterError(code: "sms_in_progress", message: "An SMS compose sheet is already open.", details: nil))
            return
          }

          let compose = MFMessageComposeViewController()
          compose.recipients = numbers
          compose.body = message
          compose.messageComposeDelegate = self

          self.pendingSmsResult = result
          controller.present(compose, animated: true)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func messageComposeViewController(
    _ controller: MFMessageComposeViewController,
    didFinishWith result: MessageComposeResult
  ) {
    controller.dismiss(animated: true)
    let pending = pendingSmsResult
    pendingSmsResult = nil
    switch result {
    case .sent:
      pending?(true)
    case .cancelled:
      pending?(FlutterError(code: "sms_cancelled", message: "The user cancelled the SMS.", details: nil))
    case .failed:
      pending?(FlutterError(code: "sms_failed", message: "Failed to send the SMS.", details: nil))
    @unknown default:
      pending?(FlutterError(code: "sms_failed", message: "Unknown SMS compose result.", details: nil))
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
