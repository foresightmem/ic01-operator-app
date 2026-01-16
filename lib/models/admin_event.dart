import 'package:flutter/material.dart';

class AdminEvent {
  final DateTime timestamp;
  final String type;
  final String title;
  final String subtitle;
  final IconData icon;

  const AdminEvent({
    required this.timestamp,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}
