// ============================================================
//  widgets/security_badge_widget.dart
//  Visual indicator shown in the chat room to communicate
//  the active security properties of the session.
// ============================================================

import 'package:flutter/material.dart';

class SecurityBadgeWidget extends StatelessWidget {
  const SecurityBadgeWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF00D4AA).withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFF00D4AA).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: const Column(
        children: [
          _BadgeRow(
            icon: Icons.lock,
            text: 'End-to-End Encrypted (AES-256-GCM)',
          ),
          SizedBox(height: 4),
          _BadgeRow(
            icon: Icons.timer_outlined,
            text: 'One-Time Session — 10 min limit',
          ),
          SizedBox(height: 4),
          _BadgeRow(
            icon: Icons.delete_sweep_outlined,
            text: 'Messages auto-delete when session ends',
          ),
        ],
      ),
    );
  }
}

class _BadgeRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _BadgeRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 13, color: const Color(0xFF00D4AA)),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            color: Color(0xFF00D4AA),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
