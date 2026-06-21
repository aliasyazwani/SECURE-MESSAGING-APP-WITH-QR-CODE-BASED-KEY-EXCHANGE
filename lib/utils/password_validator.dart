
class PasswordValidator {
  static String? validate(String password) {
    // Check empty
    if (password.isEmpty) {
      return "Password cannot be empty";
    }

    // Minimum length
    if (password.length < 8) {
      return "Password must be at least 8 characters";
    }

    // Uppercase check
    if (!password.contains(RegExp(r'[A-Z]'))) {
      return "Must include at least 1 uppercase letter";
    }

    // Lowercase check
    if (!password.contains(RegExp(r'[a-z]'))) {
      return "Must include at least 1 lowercase letter";
    }

    // Number check
    if (!password.contains(RegExp(r'[0-9]'))) {
      return "Must include at least 1 number";
    }

    // Special character check
    if (!password.contains(RegExp(r'[!@#\$%^&*(),.?":{}|<>]'))) {
      return "Must include at least 1 special character";
    }

    // If all valid
    return null;
  }
}