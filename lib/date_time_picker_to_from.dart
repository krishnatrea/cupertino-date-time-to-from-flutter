import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'dart:math' as math;

const double _kItemExtent = 32.0;
// From the picker's intrinsic content size constraint.
const double _kPickerWidth = 320.0;
const double _kPickerHeight = 316.0;
const bool _kUseMagnifier = true;
const double _kMagnification = 2.35 / 2.1;
const double _kDatePickerPadSize = 12.0;
// The density of a date picker is different from a generic picker.
// Eyeballed from iOS.
const double _kSqueeze = 1.25;

const TextStyle _kDefaultPickerTextStyle = TextStyle(
  letterSpacing: -0.83,
);

// The item height is 32 and the magnifier height is 34, from
// iOS simulators with "Debug View Hierarchy".
// And the magnified fontSize by [_kTimerPickerMagnification] conforms to the
// iOS 14 native style by eyeball test.
const double _kTimerPickerMagnification = 34 / 32;
// Minimum horizontal padding between [CupertinoTimerPicker]
//
// It shouldn't actually be hard-coded for direct use, and the perfect solution
// should be to calculate the values that match the magnified values by
// offAxisFraction and _kSqueeze.
// Such calculations are complex, so we'll hard-code them for now.
const double _kTimerPickerMinHorizontalPadding = 30;
// Half of the horizontal padding value between the timer picker's columns.
const double _kTimerPickerHalfColumnPadding = 4;
// The horizontal padding between the timer picker's number label and its
// corresponding unit label.
const double _kTimerPickerLabelPadSize = 6;
const double _kTimerPickerLabelFontSize = 17.0;

// The width of each column of the countdown time picker.
const double _kTimerPickerColumnIntrinsicWidth = 106;

TextStyle _themeTextStyle(BuildContext context, {bool isValid = true}) {
  final TextStyle style =
      CupertinoTheme.of(context).textTheme.dateTimePickerTextStyle;
  return isValid
      ? style.copyWith(
          color: CupertinoDynamicColor.maybeResolve(style.color, context))
      : style.copyWith(
          color: CupertinoDynamicColor.resolve(
              CupertinoColors.inactiveGray, context));
}

void _animateColumnControllerToItem(
    FixedExtentScrollController controller, int targetItem) {
  controller.animateToItem(
    targetItem,
    curve: Curves.easeInOut,
    duration: const Duration(milliseconds: 200),
  );
}

const Widget _startSelectionOverlay =
    CupertinoPickerDefaultSelectionOverlay(capEndEdge: false);
const Widget _centerSelectionOverlay = CupertinoPickerDefaultSelectionOverlay(
    capStartEdge: false, capEndEdge: false);
const Widget _endSelectionOverlay =
    CupertinoPickerDefaultSelectionOverlay(capStartEdge: false);

class _DatePickerLayoutDelegate extends MultiChildLayoutDelegate {
  _DatePickerLayoutDelegate({
    required this.columnWidths,
    required this.textDirectionFactor,
  })  : assert(columnWidths != null),
        assert(textDirectionFactor != null);

  // The list containing widths of all columns.
  final List<double> columnWidths;

  // textDirectionFactor is 1 if text is written left to right, and -1 if right to left.
  final int textDirectionFactor;

  @override
  void performLayout(Size size) {
    double remainingWidth = size.width;

    for (int i = 0; i < columnWidths.length; i++) {
      remainingWidth -= columnWidths[i] + _kDatePickerPadSize * 2;
    }

    double currentHorizontalOffset = 0.0;

    for (int i = 0; i < columnWidths.length; i++) {
      final int index =
          textDirectionFactor == 1 ? i : columnWidths.length - i - 1;

      double childWidth = columnWidths[index] + _kDatePickerPadSize * 2;
      if (index == 0 || index == columnWidths.length - 1) {
        childWidth += remainingWidth / 2;
      }

      // We can't actually assert here because it would break things badly for
      // semantics, which will expect that we laid things out here.
      assert(() {
        if (childWidth < 0) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: FlutterError(
                'Insufficient horizontal space to render the '
                'CupertinoDatePicker because the parent is too narrow at '
                '${size.width}px.\n'
                'An additional ${-remainingWidth}px is needed to avoid '
                'overlapping columns.',
              ),
            ),
          );
        }
        return true;
      }());
      layoutChild(index,
          BoxConstraints.tight(Size(math.max(0.0, childWidth), size.height)));
      positionChild(index, Offset(currentHorizontalOffset, 0.0));
      currentHorizontalOffset += childWidth;
    }
  }

  @override
  bool shouldRelayout(_DatePickerLayoutDelegate oldDelegate) {
    return columnWidths != oldDelegate.columnWidths ||
        textDirectionFactor != oldDelegate.textDirectionFactor;
  }
}

enum _PickerColumnType {
  // Medium date column in dateAndTime mode.
  date,
  // Hour column in time and dateAndTime mode.
  time,
}

typedef ValueChangedWithTime<Q, P> = void Function(
    Q startDateTime, P endDateTime);

class CupertinoDateTimeToFromPicker extends StatefulWidget {
  CupertinoDateTimeToFromPicker({
    super.key,
    required this.onDateTimeChanged,
    DateTime? initialDate,
    TimeOfDay? initialStartTime,
    TimeOfDay? initialEndTime,
    this.minimumDate,
    this.maximumDate,
    this.minimumYear = 1,
    this.maximumYear,
    this.minuteInterval = 15,
    this.dateOrder,
    this.backgroundColor,
  })  : this.initialDate = initialDate ?? DateTime.now(),
        this.initialStartTime = initialStartTime ?? TimeOfDay.now(),
        this.initialEndTime = initialEndTime ?? TimeOfDay.now();

  final DateTime initialDate;

  final TimeOfDay initialStartTime;

  final TimeOfDay initialEndTime;

  final DateTime? minimumDate;

  final DateTime? maximumDate;

  final int minimumYear;

  final int? maximumYear;

  final int minuteInterval;

  final DatePickerDateOrder? dateOrder;

  final ValueChangedWithTime<DateTime, DateTime> onDateTimeChanged;

  final Color? backgroundColor;

  @override
  State<CupertinoDateTimeToFromPicker> createState() =>
      _CupertinoDateTimeToFromPickerState();

  static double _getColumnWidth(
    _PickerColumnType columnType,
    CupertinoLocalizations localizations,
    BuildContext context,
  ) {
    String longestText = '';

    switch (columnType) {
      case _PickerColumnType.date:
        // Measuring the length of all possible date is impossible, so here
        // just some dates are measured.
        for (int i = 1; i <= 12; i++) {
          // An arbitrary date.
          final String date =
              localizations.datePickerMediumDate(DateTime(2018, i, 25));
          if (longestText.length < date.length) {
            longestText = date;
          }
        }
        break;
      case _PickerColumnType.time:
        String hourLongestText = "";
        String minuteLongestText = "";
        String separator = ":";
        String dayPeriod = "";
        for (int i = 0; i < 24; i++) {
          final String hour = localizations.datePickerHour(i);
          if (hourLongestText.length < hour.length) {
            hourLongestText = hour;
          }
        }
        for (int i = 0; i < 60; i++) {
          final String minute = localizations.datePickerMinute(i);
          if (minuteLongestText.length < minute.length) {
            minuteLongestText = minute;
          }
        }

        longestText = "$hourLongestText$separator$minuteLongestText";
        break;
    }

    assert(longestText != '', 'column type is not appropriate');

    return TextPainter.computeMaxIntrinsicWidth(
      text: TextSpan(
        style: _themeTextStyle(context),
        text: longestText,
      ),
      textDirection: Directionality.of(context),
    );
  }
}

typedef _ColumnBuilder = Widget Function(double offAxisFraction,
    TransitionBuilder itemPositioningBuilder, Widget selectionOverlay);

class _CupertinoDateTimeToFromPickerState
    extends State<CupertinoDateTimeToFromPicker> {
  // Fraction of the farthest column's vanishing point vs its width. Eyeballed
  // vs iOS.
  static const double _kMaximumOffAxisFraction = 0.45;

  late int textDirectionFactor;
  late CupertinoLocalizations localizations;

  // Alignment based on text direction. The variable name is self descriptive,
  // however, when text direction is rtl, alignment is reversed.
  late Alignment alignCenterLeft;
  late Alignment alignCenterRight;

  // Read this out when the state is initially created. Changes in initialDateTime
  // in the widget after first build is ignored.
  late DateTime initialDate;
  late TimeOfDay initialStartTime;
  late TimeOfDay initialEndTime;

  late FixedExtentScrollController dateController;
  late FixedExtentScrollController startTimeController;
  late FixedExtentScrollController endTimeController;

  int get selectedDateFromInitial {
    return dateController.hasClients ? dateController.selectedItem : 0;
  }

  bool isDatePickerScrolling = false;
  bool isStartTimePickerScrolling = false;
  bool isEndTimeScrolling = false;

  bool get isScrolling {
    return isDatePickerScrolling ||
        isStartTimePickerScrolling ||
        isEndTimeScrolling;
  }

  // The estimated width of columns.
  final Map<int, double> estimatedColumnWidths = <int, double>{};

  @override
  void initState() {
    super.initState();
    initialDate = widget.initialDate;
    initialStartTime = widget.initialStartTime;
    initialEndTime = widget.initialEndTime;

    dateController = FixedExtentScrollController();
    startTimeController = FixedExtentScrollController();
    endTimeController = FixedExtentScrollController();

    PaintingBinding.instance.systemFonts.addListener(_handleSystemFontsChange);
  }

  void _handleSystemFontsChange() {
    setState(() {
      // System fonts change might cause the text layout width to change.
      // Clears cached width to ensure that they get recalculated with the
      // new system fonts.
      estimatedColumnWidths.clear();
    });
  }

  @override
  void dispose() {
    dateController.dispose();
    startTimeController.dispose();
    endTimeController.dispose();
    PaintingBinding.instance.systemFonts
        .removeListener(_handleSystemFontsChange);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    textDirectionFactor =
        Directionality.of(context) == TextDirection.ltr ? 1 : -1;
    localizations = CupertinoLocalizations.of(context);

    alignCenterLeft =
        textDirectionFactor == 1 ? Alignment.centerLeft : Alignment.centerRight;
    alignCenterRight =
        textDirectionFactor == 1 ? Alignment.centerRight : Alignment.centerLeft;

    estimatedColumnWidths.clear();
  }

  // Lazily calculate the column width of the column being displayed only.
  double _getEstimatedColumnWidth(_PickerColumnType columnType) {
    if (estimatedColumnWidths[columnType.index] == null) {
      estimatedColumnWidths[columnType.index] =
          CupertinoDateTimeToFromPicker._getColumnWidth(
              columnType, localizations, context);
    }
    return estimatedColumnWidths[columnType.index]!;
  }

  int get selectedDate =>
      dateController.hasClients ? dateController.selectedItem : 0;
  int get selectedStartTime =>
      startTimeController.hasClients ? startTimeController.selectedItem : 0;
  int get selectedEndTime =>
      endTimeController.hasClients ? endTimeController.selectedItem : 0;

  //  Only reports datetime change when the date time is valid.
  void _onSelectedItemChange(int index) {
    final DateTime selected = DateTime(
        initialDate.year, initialDate.month, initialDate.day + selectedDate);

    final TimeOfDay selectedS = addTime(
        TimeOfDay(hour: initialStartTime.hour, minute: 0),
        minutes: selectedStartTime * widget.minuteInterval);

    final TimeOfDay selectedE = addTime(
        TimeOfDay(hour: initialStartTime.hour, minute: 0),
        minutes: selectedEndTime * widget.minuteInterval);

    final bool isDateInvalid =
        (widget.minimumDate?.isAfter(selected) ?? false) ||
            (widget.maximumDate?.isBefore(selected) ?? false);

    if (isDateInvalid) {
      return;
    }
    final startDate = DateTime(selected.year, selected.month, selected.day,
        selectedS.hour, selectedS.minute);

    final endDate = DateTime(selected.year, selected.month, selected.day,
        selectedE.hour, selectedE.minute);

    widget.onDateTimeChanged(startDate, endDate);
  }

  // Builds the date column. The date is displayed in medium date format (e.g. Fri Aug 31).
  Widget _buildMediumDatePicker(double offAxisFraction,
      TransitionBuilder itemPositioningBuilder, Widget selectionOverlay) {
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification notification) {
        if (notification is ScrollStartNotification) {
          isDatePickerScrolling = true;
        } else if (notification is ScrollEndNotification) {
          isDatePickerScrolling = false;
          _pickerDidStopScrolling();
        }

        return false;
      },
      child: CupertinoPicker.builder(
        scrollController: dateController,
        offAxisFraction: offAxisFraction,
        itemExtent: _kItemExtent,
        useMagnifier: _kUseMagnifier,
        magnification: _kMagnification,
        backgroundColor: widget.backgroundColor,
        squeeze: _kSqueeze,
        onSelectedItemChanged: (int index) {
          _onSelectedItemChange(index);
        },
        itemBuilder: (BuildContext context, int index) {
          final DateTime rangeStart = DateTime(
            initialDate.year,
            initialDate.month,
            initialDate.day + index,
          );

          // Exclusive.
          final DateTime rangeEnd = DateTime(
            initialDate.year,
            initialDate.month,
            initialDate.day + index + 1,
          );

          final DateTime now = DateTime.now();

          if (widget.minimumDate?.isBefore(rangeEnd) == false) {
            return null;
          }
          if (widget.maximumDate?.isAfter(rangeStart) == false) {
            return null;
          }

          final String dateText =
              rangeStart == DateTime(now.year, now.month, now.day)
                  ? localizations.todayLabel
                  : localizations.datePickerMediumDate(rangeStart);

          return itemPositioningBuilder(
            context,
            Text(dateText, style: _themeTextStyle(context)),
          );
        },
        selectionOverlay: selectionOverlay,
      ),
    );
  }

  Widget _buildStartTimePicker(double offAxisFraction,
      TransitionBuilder itemPositioningBuilder, Widget selectionOverlay) {
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification notification) {
        if (notification is ScrollStartNotification) {
          isDatePickerScrolling = true;
        } else if (notification is ScrollEndNotification) {
          isDatePickerScrolling = false;
          _pickerDidStopScrolling();
        }

        return false;
      },
      child: CupertinoPicker.builder(
        scrollController: startTimeController,
        offAxisFraction: offAxisFraction,
        itemExtent: _kItemExtent,
        useMagnifier: _kUseMagnifier,
        magnification: _kMagnification,
        backgroundColor: widget.backgroundColor,
        squeeze: _kSqueeze,
        onSelectedItemChanged: (int index) {
          _onSelectedItemChange(index);
        },
        itemBuilder: (BuildContext context, int index) {
          final TimeOfDay rangeStart = addTime(
              TimeOfDay(hour: initialStartTime.hour, minute: 0),
              minutes: index * widget.minuteInterval);

          final String timeText =
              "${localizations.datePickerHour(rangeStart.hour)} ${localizations.datePickerMinute(rangeStart.minute)}";

          return itemPositioningBuilder(
            context,
            Text(timeText, style: _themeTextStyle(context)),
          );
        },
        selectionOverlay: selectionOverlay,
      ),
    );
  }

  Widget _buildEndTimePicker(double offAxisFraction,
      TransitionBuilder itemPositioningBuilder, Widget selectionOverlay) {
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification notification) {
        if (notification is ScrollStartNotification) {
          isDatePickerScrolling = true;
        } else if (notification is ScrollEndNotification) {
          isDatePickerScrolling = false;
          _pickerDidStopScrolling();
        }

        return false;
      },
      child: CupertinoPicker.builder(
        scrollController: endTimeController,
        offAxisFraction: offAxisFraction,
        itemExtent: _kItemExtent,
        useMagnifier: _kUseMagnifier,
        magnification: _kMagnification,
        backgroundColor: widget.backgroundColor,
        squeeze: _kSqueeze,
        onSelectedItemChanged: (int index) {
          _onSelectedItemChange(index);
        },
        itemBuilder: (BuildContext context, int index) {
          final TimeOfDay rangeStart = addTime(
              TimeOfDay(hour: initialEndTime.hour, minute: 0),
              minutes: index * widget.minuteInterval);
          final String timeText =
              "${localizations.datePickerHour(rangeStart.hour)} ${localizations.datePickerMinute(rangeStart.minute)}";

          return itemPositioningBuilder(
            context,
            Text(timeText, style: _themeTextStyle(context)),
          );
        },
        selectionOverlay: selectionOverlay,
      ),
    );
  }

  // One or more pickers have just stopped scrolling.
  void _pickerDidStopScrolling() {
    // Call setState to update the greyed out date/hour/minute/meridiem.
    setState(() {});

    if (isScrolling) {
      return;
    }

    // Whenever scrolling lands on an invalid entry, the picker
    // automatically scrolls to a valid one.
    final DateTime selectDate = DateTime(
        initialDate.year, initialDate.month, initialDate.day + selectedDate);

    final bool minCheck = widget.minimumDate?.isAfter(selectDate) ?? false;
    final bool maxCheck = widget.maximumDate?.isBefore(selectDate) ?? false;

    if (minCheck || maxCheck) {
      // We have minCheck === !maxCheck.
      final DateTime targetDate =
          minCheck ? widget.minimumDate! : widget.maximumDate!;
      _scrollToDate(targetDate, selectDate, minCheck);
    }
  }

  void _scrollToDate(DateTime newDate, DateTime fromDate, bool minCheck) {
    assert(newDate != null);
    SchedulerBinding.instance.addPostFrameCallback((Duration timestamp) {
      if (fromDate.year != newDate.year ||
          fromDate.month != newDate.month ||
          fromDate.day != newDate.day) {
        _animateColumnControllerToItem(dateController, selectedDateFromInitial);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
// ------------------
    // Widths of the columns in this picker, ordered from left to right.
    final List<double> columnWidths = <double>[
      _getEstimatedColumnWidth(_PickerColumnType.time),
      _getEstimatedColumnWidth(_PickerColumnType.time),
    ];

    // Swap the hours and minutes if RTL to ensure they are in the correct position.
    final List<_ColumnBuilder> pickerBuilders = <_ColumnBuilder>[
      _buildStartTimePicker,
      _buildEndTimePicker
    ];

    // Adds medium date column if the picker's mode is date and time.
    if (localizations.datePickerDateTimeOrder ==
            DatePickerDateTimeOrder.time_dayPeriod_date ||
        localizations.datePickerDateTimeOrder ==
            DatePickerDateTimeOrder.dayPeriod_time_date) {
      pickerBuilders.add(_buildMediumDatePicker);
      columnWidths.add(_getEstimatedColumnWidth(_PickerColumnType.date));
    } else {
      pickerBuilders.insert(0, _buildMediumDatePicker);
      columnWidths.insert(0, _getEstimatedColumnWidth(_PickerColumnType.date));
    }
// ---------------
    final List<Widget> pickers = <Widget>[];

    for (int i = 0; i < columnWidths.length; i++) {
      double offAxisFraction = 0.0;
      Widget selectionOverlay = _centerSelectionOverlay;
      if (i == 0) {
        offAxisFraction = -_kMaximumOffAxisFraction * textDirectionFactor;
        selectionOverlay = _startSelectionOverlay;
      } else if (i >= 2 || columnWidths.length == 2) {
        offAxisFraction = _kMaximumOffAxisFraction * textDirectionFactor;
      }

      EdgeInsets padding = const EdgeInsets.only(right: _kDatePickerPadSize);
      if (i == columnWidths.length - 1) {
        padding = padding.flipped;
        selectionOverlay = _endSelectionOverlay;
      }
      if (textDirectionFactor == -1) {
        padding = padding.flipped;
      }

      pickers.add(LayoutId(
        id: i,
        child: pickerBuilders[i](
          offAxisFraction,
          (BuildContext context, Widget? child) {
            return Container(
              alignment: i == columnWidths.length - 1
                  ? alignCenterLeft
                  : alignCenterRight,
              padding: padding,
              child: Container(
                alignment: i == columnWidths.length - 1
                    ? alignCenterLeft
                    : alignCenterRight,
                width: i == 0 || i == columnWidths.length - 1
                    ? null
                    : columnWidths[i] + _kDatePickerPadSize,
                child: child,
              ),
            );
          },
          selectionOverlay,
        ),
      ));
    }

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaleFactor: 1.0),
      child: DefaultTextStyle.merge(
        style: _kDefaultPickerTextStyle,
        child: CustomMultiChildLayout(
          delegate: _DatePickerLayoutDelegate(
            columnWidths: columnWidths,
            textDirectionFactor: textDirectionFactor,
          ),
          children: pickers,
        ),
      ),
    );
  }
}

TimeOfDay addTime(TimeOfDay time, {int hours = 0, int minutes = 0}) =>
    TimeOfDay(
        hour: (time.hour + hours) + minutes ~/ 60,
        minute: (time.minute + minutes) % 60);
