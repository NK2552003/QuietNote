import 'package:flutter/material.dart';
import 'flutter_ui.dart';

/// Single-file master reference showcasing all Flutter UI foundation components.
class FlutterUiExampleApp extends StatefulWidget {
  const FlutterUiExampleApp({super.key});

  @override
  State<FlutterUiExampleApp> createState() => _FlutterUiExampleAppState();
}

class _FlutterUiExampleAppState extends State<FlutterUiExampleApp> {
  bool _isDark = true;
  bool _checkboxVal = true;
  bool _switchVal = true;
  double _sliderVal = 45;
  String _inputText = 'NVDA';
  String _selectVal = 'usd';
  String _radioVal = 'market';
  List<String> _tags = <String>['trading', 'breakout'];
  int _tabIndex = 0;
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    final UiTheme theme = _isDark ? UiTheme.dark() : UiTheme.light();
    return UiApp(
      theme: theme,
      builder: (BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Flutter UI Complete Component Library'),
          actions: <Widget>[
            IconButton(
              icon: Icon(_isDark ? Icons.light_mode : Icons.dark_mode),
              onPressed: () => setState(() => _isDark = !_isDark),
            ),
          ],
        ),
        body: ListView(
          padding: EdgeInsets.all(context.sp(theme.spacing.lg)),
          children: <Widget>[
            _buildSection(
              context,
              title: '1. Buttons & Actions',
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  UiButton(label: 'Primary Action', variant: UiVariant.primary, onPressed: () {}),
                  UiButton(label: 'Secondary Action', variant: UiVariant.secondary, onPressed: () {}),
                  UiButton(label: 'Outline Action', variant: UiVariant.outline, onPressed: () {}),
                  UiButton(label: 'Ghost Action', variant: UiVariant.ghost, onPressed: () {}),
                  UiButton(label: 'Destructive', variant: UiVariant.destructive, onPressed: () {}),
                  const UiButton(label: 'Disabled', variant: UiVariant.primary, onPressed: null),
                  UiIconButton(icon: Icons.star_border, tooltip: 'Favorite', onPressed: () {}),
                  const UiToggleGroup<String>(
                    value: '1D',
                    options: <UiToggleOption<String>>[
                      UiToggleOption(value: '1D', label: '1D'),
                      UiToggleOption(value: '1W', label: '1W'),
                      UiToggleOption(value: '1M', label: '1M'),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: context.sp(theme.spacing.xl)),
            _buildSection(
              context,
              title: '2. Badges & Callouts',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      UiBadge(label: 'Bullish', intent: UiIntent.bullish),
                      UiBadge(label: 'Bearish', intent: UiIntent.bearish),
                      UiBadge(label: 'Neutral', intent: UiIntent.neutral),
                      UiBadge(label: 'Warning', intent: UiIntent.warning),
                      UiBadge(label: 'Primary', intent: UiIntent.primary),
                    ],
                  ),
                  SizedBox(height: context.sp(theme.spacing.md)),
                  const UiCallout(
                    title: 'Risk Warning',
                    message: 'High volatility expected during upcoming FOMC interest rate decision.',
                    intent: UiIntent.warning,
                  ),
                ],
              ),
            ),
            SizedBox(height: context.sp(theme.spacing.xl)),
            _buildSection(
              context,
              title: '3. Input Controls',
              child: Column(
                children: <Widget>[
                  UiInput(
                    hintText: 'Search tickers...',
                    value: _inputText,
                    leadingIcon: Icons.search,
                    onChanged: (v) => setState(() => _inputText = v),
                  ),
                  SizedBox(height: context.sp(theme.spacing.md)),
                  UiSearchField(
                    hintText: 'Search tickers, setups or strategies...',
                    onChanged: (v) {},
                  ),
                  SizedBox(height: context.sp(theme.spacing.md)),
                  UiSelect<String>(
                    value: _selectVal,
                    hintText: 'Select Base Currency',
                    options: const <UiOption<String>>[
                      UiOption(value: 'usd', label: 'USD - United States Dollar'),
                      UiOption(value: 'eur', label: 'EUR - Euro'),
                      UiOption(value: 'gbp', label: 'GBP - British Pound'),
                    ],
                    onChanged: (v) => setState(() => _selectVal = v),
                  ),
                  SizedBox(height: context.sp(theme.spacing.md)),
                  UiTagInput(
                    tags: _tags,
                    hintText: 'Add tag...',
                    onChanged: (tags) => setState(() => _tags = tags),
                  ),
                  SizedBox(height: context.sp(theme.spacing.md)),
                  UiRadioGroup<String>(
                    value: _radioVal,
                    onChanged: (v) => setState(() => _radioVal = v),
                    options: const <UiOption<String>>[
                      UiOption(value: 'market', label: 'Market Order'),
                      UiOption(value: 'limit', label: 'Limit Order'),
                    ],
                  ),
                  SizedBox(height: context.sp(theme.spacing.md)),
                  UiCheckbox(
                    value: _checkboxVal,
                    label: 'Enable auto-refresh',
                    onChanged: (v) => setState(() => _checkboxVal = v),
                  ),
                  SizedBox(height: context.sp(theme.spacing.md)),
                  UiSwitch(
                    value: _switchVal,
                    label: 'Push Notifications',
                    onChanged: (v) => setState(() => _switchVal = v),
                  ),
                  SizedBox(height: context.sp(theme.spacing.md)),
                  UiSlider(
                    value: _sliderVal,
                    min: 0,
                    max: 100,
                    label: 'Risk Percentage',
                    onChanged: (v) => setState(() => _sliderVal = v),
                  ),
                  SizedBox(height: context.sp(theme.spacing.md)),
                  const UiTextarea(
                    hintText: 'Write trading thesis or journal notes...',
                    rows: 3,
                  ),
                ],
              ),
            ),
            SizedBox(height: context.sp(theme.spacing.xl)),
            _buildSection(
              context,
              title: '4. Avatars & Metric Cards',
              child: Column(
                children: <Widget>[
                  const Row(
                    children: <Widget>[
                      UiAvatar(name: 'Nitish Kumar', size: UiSize.sm),
                      SizedBox(width: 12),
                      UiAvatar(name: 'Nitish Kumar', size: UiSize.md),
                      SizedBox(width: 12),
                      UiAvatar(name: 'Nitish Kumar', size: UiSize.lg),
                    ],
                  ),
                  SizedBox(height: context.sp(theme.spacing.md)),
                  const UiMetricCard(
                    label: 'Total Portfolio Value',
                    value: '\$142,850.25',
                    delta: 14.2,
                  ),
                  SizedBox(height: context.sp(theme.spacing.md)),
                  const UiCard(
                    title: 'Trade Summary Card',
                    subtitle: 'Execution details & risk metrics',
                    child: Text('Position sizing optimal at 2.5% max risk per trade.'),
                  ),
                ],
              ),
            ),
            SizedBox(height: context.sp(theme.spacing.xl)),
            _buildSection(
              context,
              title: '5. Navigation & Layout',
              child: Column(
                children: <Widget>[
                  UiTabs(
                    items: const <UiTabItem>[
                      UiTabItem(label: 'Overview', content: Text('Overview Tab Panel Content')),
                      UiTabItem(label: 'Analytics', content: Text('Analytics Tab Panel Content')),
                      UiTabItem(label: 'Settings', content: Text('Settings Tab Panel Content')),
                    ],
                    initialIndex: _tabIndex,
                    onChanged: (i) => setState(() => _tabIndex = i),
                  ),
                  SizedBox(height: context.sp(theme.spacing.md)),
                  const UiAccordion(
                    items: <UiAccordionItem>[
                      UiAccordionItem(
                        title: 'Trading Rules & Strategy Parameters',
                        content: Text('1. Max 2% risk per trade. 2. Cut losses fast. 3. Let winners run.'),
                      ),
                    ],
                  ),
                  SizedBox(height: context.sp(theme.spacing.md)),
                  const UiBreadcrumbs(
                    crumbs: <UiCrumb>[
                      UiCrumb(label: 'Home'),
                      UiCrumb(label: 'Journal'),
                      UiCrumb(label: 'Trade #142'),
                    ],
                  ),
                  SizedBox(height: context.sp(theme.spacing.md)),
                  UiPagination(
                    page: _currentPage,
                    pageCount: 5,
                    onPageChanged: (p) => setState(() => _currentPage = p),
                  ),
                ],
              ),
            ),
            SizedBox(height: context.sp(theme.spacing.xl)),
            _buildSection(
              context,
              title: '6. Data Display & Tables',
              child: Column(
                children: <Widget>[
                  UiTable<Map<String, String>>(
                    rows: const <Map<String, String>>[
                      {'ticker': 'AAPL', 'price': '\$224.30', 'change': '+1.8%'},
                      {'ticker': 'TSLA', 'price': '\$210.15', 'change': '-2.4%'},
                      {'ticker': 'NVDA', 'price': '\$132.80', 'change': '+4.1%'},
                    ],
                    columns: <UiTableColumn<Map<String, String>>>[
                      UiTableColumn<Map<String, String>>(
                        header: 'Ticker',
                        cell: (ctx, item) => Text(item['ticker']!, style: ctx.uiText.bodyStrong),
                      ),
                      UiTableColumn<Map<String, String>>(
                        header: 'Price',
                        cell: (ctx, item) => Text(item['price']!),
                      ),
                      UiTableColumn<Map<String, String>>(
                        header: 'Change',
                        cell: (ctx, item) => Text(
                          item['change']!,
                          style: TextStyle(
                            color: item['change']!.startsWith('+')
                                ? ctx.uiColors.bullish
                                : ctx.uiColors.bearish,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: context.sp(theme.spacing.md)),
                  const UiProgressBar(value: 0.72, label: 'Monthly Goal Target'),
                  SizedBox(height: context.sp(theme.spacing.md)),
                  const UiCategoryBar(
                    segments: <UiCategorySegment>[
                      UiCategorySegment(value: 65, label: 'Win', color: Colors.green),
                      UiCategorySegment(value: 35, label: 'Loss', color: Colors.red),
                    ],
                  ),
                  SizedBox(height: context.sp(theme.spacing.md)),
                  const UiTracker(
                    blocks: <UiTrackerBlock>[
                      UiTrackerBlock(intent: UiIntent.bullish),
                      UiTrackerBlock(intent: UiIntent.bullish),
                      UiTrackerBlock(intent: UiIntent.bearish),
                      UiTrackerBlock(intent: UiIntent.bullish),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: context.sp(theme.spacing.xl)),
            _buildSection(
              context,
              title: '7. Charts & Visualization',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Candlestick Chart', style: context.uiText.subheading),
                  SizedBox(height: context.sp(theme.spacing.sm)),
                  UiCandleChart(
                    height: 160,
                    candles: <UiCandle>[
                      UiCandle(time: DateTime.now().subtract(const Duration(days: 2)), open: 120, high: 126, low: 119, close: 125),
                      UiCandle(time: DateTime.now().subtract(const Duration(days: 1)), open: 125, high: 130, low: 124, close: 128),
                    ],
                  ),
                  SizedBox(height: context.sp(theme.spacing.md)),
                  Text('Sparkline Chart', style: context.uiText.subheading),
                  SizedBox(height: context.sp(theme.spacing.sm)),
                  const UiSparkChart(
                    values: <double>[120, 125, 122, 130, 128, 135, 142],
                    height: 60,
                  ),
                  SizedBox(height: context.sp(theme.spacing.md)),
                  Text('Donut Chart', style: context.uiText.subheading),
                  SizedBox(height: context.sp(theme.spacing.sm)),
                  const SizedBox(
                    height: 140,
                    child: UiDonutChart(
                      slices: <UiDonutSlice>[
                        UiDonutSlice(label: 'Tech', value: 60, color: Colors.blue),
                        UiDonutSlice(label: 'Energy', value: 25, color: Colors.orange),
                        UiDonutSlice(label: 'Cash', value: 15, color: Colors.green),
                      ],
                    ),
                  ),
                  SizedBox(height: context.sp(theme.spacing.md)),
                  Text('Node Graph Canvas', style: context.uiText.subheading),
                  SizedBox(height: context.sp(theme.spacing.sm)),
                  const UiGraphCanvas(
                    height: 140,
                    nodes: <UiGraphNode>[
                      UiGraphNode(id: 'n1', label: 'NVDA', weight: 1.5, intent: UiIntent.bullish),
                      UiGraphNode(id: 'n2', label: 'AI Strategy', weight: 1.2, intent: UiIntent.primary),
                    ],
                    edges: <UiGraphEdge>[
                      UiGraphEdge(from: 'n1', to: 'n2'),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: context.sp(theme.spacing.xl)),
            _buildSection(
              context,
              title: '8. Overlays & Feedback',
              child: Wrap(
                spacing: 12,
                children: <Widget>[
                  UiButton(
                    label: 'Trigger Dialog Modal',
                    variant: UiVariant.outline,
                    onPressed: () {
                      UiDialog.confirm(
                        context,
                        title: 'Order Confirmation',
                        description: 'Execute Market Order: BUY 100 NVDA @ \$135.00?',
                      );
                    },
                  ),
                  UiButton(
                    label: 'Trigger Drawer Panel',
                    variant: UiVariant.secondary,
                    onPressed: () {
                      UiDrawer.show(
                        context,
                        title: 'Position Settings',
                        child: Padding(
                          padding: EdgeInsets.all(context.sp(theme.spacing.md)),
                          child: const Text('Configure trailing stop and price alert thresholds.'),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context, {required String title, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: context.uiText.heading),
        SizedBox(height: context.sp(context.uiSpace.sm)),
        child,
      ],
    );
  }
}
