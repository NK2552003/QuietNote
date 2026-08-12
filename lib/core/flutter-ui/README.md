# Flutter UI

A themed, responsive Flutter component library. One file per component, all
styling driven by design tokens (`theme/ui_tokens.dart`) — components never
hardcode colors, spacing, radii, or typography.

```dart
import 'package:your_app/flutter-ui/flutter_ui.dart';

UiThemeScope(
  theme: UiTheme.light(),
  child: MaterialApp(home: MyPage()),
);
```

## Structure

```text
flutter-ui/
  flutter_ui.dart        barrel export (import this)
  theme/
    ui_tokens.dart       palettes, spacing, radii, typography, sizes, motion
    ui_theme.dart        UiTheme + UiThemeScope + context extensions
    ui_responsive.dart   breakpoints, context.sp/sz/radius, r.pick<T>()
  components/            one widget per file
```

## Component map (Tremor -> Flutter)

| Tremor component | Flutter widget | File |
| --- | --- | --- |
| Accordion | `UiAccordion` | `ui_accordion.dart` |
| AreaChart | `UiAreaChart` | `ui_area_chart.dart` |
| Badge | `UiBadge` | `ui_badge.dart` |
| BarChart | `UiBarChart` | `ui_bar_chart.dart` |
| BarList | `UiBarList` | `ui_bar_list.dart` |
| Button | `UiButton` | `ui_button.dart` |
| Calendar | `UiCalendar` | `ui_calendar.dart` |
| Callout | `UiCallout` | `ui_callout.dart` |
| Card | `UiCard` | `ui_card.dart` |
| CategoryBar | `UiCategoryBar` | `ui_category_bar.dart` |
| Checkbox | `UiCheckbox` | `ui_checkbox.dart` |
| ComboChart | `UiComboChart` | `ui_combo_chart.dart` |
| DatePicker | `UiDatePicker` | `ui_date_picker.dart` |
| DateRangePicker | `UiDateRangePicker` | `ui_date_range_picker.dart` |
| Dialog | `UiDialog` (`showUiDialog`) | `ui_dialog.dart` |
| Divider | `UiDivider` | `ui_divider.dart` |
| DonutChart | `UiDonutChart` | `ui_donut_chart.dart` |
| Drawer | `UiDrawerPanel` (`showUiDrawer`) | `ui_drawer.dart` |
| DropdownMenu | `UiDropdownMenu` | `ui_dropdown_menu.dart` |
| Input | `UiInput` | `ui_input.dart` |
| Label | `UiLabel` | `ui_label.dart` |
| LineChart | `UiLineChart` | `ui_line_chart.dart` |
| Popover | `UiPopover` | `ui_popover.dart` |
| ProgressBar | `UiProgressBar` | `ui_progress_bar.dart` |
| ProgressCircle | `UiProgressCircle` | `ui_progress_circle.dart` |
| RadioCardGroup | `UiRadioCardGroup` | `ui_radio_card_group.dart` |
| RadioGroup | `UiRadioGroup` | `ui_radio_group.dart` |
| Select | `UiSelect` | `ui_select.dart` |
| SelectNative | `UiSelectNative` | `ui_select_native.dart` |
| Slider | `UiSlider` | `ui_slider.dart` |
| SliderRange | `UiRangeSlider` | `ui_range_slider.dart` |
| SparkChart | `UiSparkChart` | `ui_spark_chart.dart` |
| Switch | `UiSwitch` | `ui_switch.dart` |
| Table | `UiTable` | `ui_table.dart` |
| TabNavigation | `UiTabNavigation` | `ui_tab_navigation.dart` |
| Tabs | `UiTabs` | `ui_tabs.dart` |
| Textarea | `UiTextarea` | `ui_textarea.dart` |
| Toast / Toaster | `UiToast` / `UiToastScope` | `ui_toast.dart`, `ui_toaster.dart` |
| Tooltip | `UiTooltip` | `ui_tooltip.dart` |
| Tracker | `UiTracker` | `ui_tracker.dart` |

Extras beyond Tremor: `UiAvatar`, `UiMetricCard`, `UiCardGrid`, `UiEmptyState`,
`UiSkeleton`, `UiNavShell`, `UiPage`, `UiField`, `UiGap`, `UiToggle`,
`UiToggleGroup`, `UiIconButton`.

## Behaviour notes

- **Charts** share one painter (`ui_chart_base.dart`). Hover or drag shows a
  crosshair with a value tooltip; legend entries toggle series visibility.
  Pass `interactive: false` to opt out.
- **Table** supports per-column sorting (give a column a `compare`), optional
  `pageSize` pagination, a `footer` row, and `stackOnMobile` card layout.
  Use `sortColumn` / `sortAscending` / `onSort` for server-side sorting.
- **Calendar** accepts `monthCount` for multi-month range views (stacks on
  phones), plus `markedDates` for event dots.
- **Responsive**: every size goes through `context.sp()`, `context.sz()`,
  `context.radius()`, so the whole library scales per breakpoint.
