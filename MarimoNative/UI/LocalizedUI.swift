import Foundation
import MarimoEnvironment

func localizedUI(_ key: String) -> String {
  Bundle.main.localizedString(forKey: key, value: key, table: nil)
}

func localizedUI(_ key: String, _ arguments: CVarArg...) -> String {
  String(format: localizedUI(key), locale: Locale.current, arguments: arguments)
}

func localizedPythonFailure(_ failure: PythonPreflightFailure) -> String {
  switch failure {
  case .missingExecutable(let url):
    localizedUI("Python executable is missing or not executable: %@", url.path)
  case .executableChanged(let url):
    localizedUI("The saved Python executable changed: %@", url.path)
  case .launchFailed(let message):
    localizedUI("Python check could not start: %@", message)
  case .timedOut:
    localizedUI("Python check took longer than 5 seconds.")
  case .stdoutLimitExceeded:
    localizedUI("Python check produced too much standard output.")
  case .stderrLimitExceeded:
    localizedUI("Python check produced too much error output.")
  case .nonzeroExit(let exitStatus):
    localizedUI("Python check exited with status %d.", exitStatus)
  case .invalidJSON:
    localizedUI("Python check returned an invalid response.")
  case .marimoNotInstalled:
    localizedUI("marimo 0.24.0 is not installed in this Python environment.")
  case .executableMismatch(let expected, let reported):
    localizedUI(
      "Python reported a different executable (expected %@, got %@).", expected.path,
      reported.path)
  case .unsupportedPython(let version):
    localizedUI("Python %@ is unsupported. Required: Python 3.10–3.14.", version.description)
  case .unsupportedArchitecture(let architecture):
    localizedUI("Python architecture %@ is unsupported. Required: arm64.", architecture)
  case .unsupportedMarimo(let version):
    localizedUI("marimo %@ is unsupported. Required: marimo 0.24.0.", version)
  }
}
