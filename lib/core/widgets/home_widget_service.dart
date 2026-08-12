import 'package:home_widget/home_widget.dart';

class HomeWidgetService {
  static const String _appGroupId = 'group.com.quietnote.widget';

  static Future<void> init() async {
    await HomeWidget.setAppGroupId(_appGroupId);
  }

  static Future<void> updateTopTask(String title) async {
    await HomeWidget.saveWidgetData<String>('top_task_title', title);
    await HomeWidget.updateWidget(
      name: 'TaskWidgetProvider',
      iOSName: 'TaskWidget',
    );
  }
}
