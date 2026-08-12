import 'package:flutter/material.dart';

enum ItemKind { habit, task, note, routine, goal, journal }
enum ItemStatus { active, completed, archived }

class ProductivityItem {
  const ProductivityItem({
    required this.id,
    required this.title,
    required this.kind,
    this.subtitle = '',
    this.status = ItemStatus.active,
    this.streak = 0,
    this.progress = 0,
    this.createdAt,
  });

  final String id;
  final String title;
  final ItemKind kind;
  final String subtitle;
  final ItemStatus status;
  final int streak;
  final double progress;
  final DateTime? createdAt;

  ProductivityItem copyWith({
    String? title,
    String? subtitle,
    ItemStatus? status,
    int? streak,
    double? progress,
  }) =>
      ProductivityItem(
        id: id,
        title: title ?? this.title,
        kind: kind,
        subtitle: subtitle ?? this.subtitle,
        status: status ?? this.status,
        streak: streak ?? this.streak,
        progress: progress ?? this.progress,
        createdAt: createdAt,
      );
}

extension ItemKindLabel on ItemKind {
  String get label => switch (this) {
        ItemKind.habit => 'Habit',
        ItemKind.task => 'Task',
        ItemKind.note => 'Note',
        ItemKind.routine => 'Routine',
        ItemKind.goal => 'Goal',
        ItemKind.journal => 'Journal'
      };
}

extension ItemKindIcon on ItemKind {
  IconData get icon => switch (this) {
        ItemKind.habit => Icons.repeat_rounded,
        ItemKind.task => Icons.check_circle_outline_rounded,
        ItemKind.note => Icons.notes_rounded,
        ItemKind.routine => Icons.route_rounded,
        ItemKind.goal => Icons.flag_outlined,
        ItemKind.journal => Icons.menu_book_outlined
      };
}
