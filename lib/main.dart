import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key}) : super(key: key);

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Realtime Chart'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const <Widget>[
            ChannelRawDataRealtimeChart(),
          ],
        ),
      ),
    );
  }
}

class ChannelRawDataRealtimeChart extends StatefulWidget {
  const ChannelRawDataRealtimeChart({
    Key? key,
  }) : super(key: key);

  @override
  _ChannelRawDataChartState createState() => _ChannelRawDataChartState();
}

class _ChannelRawDataChartState extends State<ChannelRawDataRealtimeChart> {
  late ZoomPanBehavior _zoomPanBehavior;
  ChartSeriesController? seriesController;
  double? oldAxisVisibleMin;
  double? oldAxisVisibleMax;
  final double loadInterval = 0.3; // sec

  late Data _data = Data.zero();
  bool isLoadMoreView = false;

  final double windowTime = 0.6;
  double nextStart = 0;
  double nextEnd = 0;
  bool hasNextWindow = true;

  late GetDataUseCase _getDataUseCase;

  @override
  void initState() {
    super.initState();

    _zoomPanBehavior = ChartZoomBehavior();
    _getDataUseCase = GetDataUseCase();

    _setupWindow(2); // 2 seconds
    _getInitialData();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 400.0,
      child: _buildInfiniteScrollingChart(),
    );
  }

  SfCartesianChart _buildInfiniteScrollingChart() {
    return SfCartesianChart(
      key: GlobalKey<State>(),
      margin: EdgeInsets.zero,
      zoomPanBehavior: _zoomPanBehavior,
      title: ChartTitle(
        text: 'Data chart',
      ),
      primaryXAxis: ChartXAxis(),
      primaryYAxis: ChartYAxis(),
      series: getSeries(),
      onActualRangeChanged: onRangeChanged,
      loadMoreIndicatorBuilder:
          (BuildContext context, ChartSwipeDirection direction) =>
              getLoadMoreIndicatorBuilder(context, direction),
    );
  }

  List<ChartSeries<Point, double>> getSeries() {
    return <ChartSeries<Point, double>>[
      LineSeries<Point, double>(
        dataSource: _data.points,
        animationDuration: 0.0,
        animationDelay: 0.0,
        emptyPointSettings: EmptyPointSettings(),
        xValueMapper: (Point point, int index) => point.x,
        yValueMapper: (Point point, int index) => point.y,
        onRendererCreated: (ChartSeriesController controller) {
          seriesController = controller;
        },
      ),
    ];
  }

  void onRangeChanged(ActualRangeChangedArgs args) {
    if (args.orientation == AxisOrientation.horizontal) {
      if (isLoadMoreView) {
        args.visibleMin = oldAxisVisibleMin;
        args.visibleMax = oldAxisVisibleMax;
      }
      if (args.visibleMin is int) {
        oldAxisVisibleMin = (args.visibleMin as int).toDouble();
      } else {
        oldAxisVisibleMin = args.visibleMin as double;
      }
      if (args.visibleMax is int) {
        oldAxisVisibleMax = (args.visibleMax as int).toDouble();
      } else {
        oldAxisVisibleMax = args.visibleMax as double;
      }
    }
    isLoadMoreView = false;
  }

  Widget getLoadMoreIndicatorBuilder(
      BuildContext context, ChartSwipeDirection direction) {
    final bool minIsVisible = oldAxisVisibleMin?.toStringAsFixed(1) ==
        _data.points.first.x.toStringAsFixed(1);
    print('>>> min: $minIsVisible >>> hasNextWindow: $hasNextWindow');
    if (direction == ChartSwipeDirection.start &&
        hasNextWindow &&
        minIsVisible) {
      return FutureBuilder<void>(
        future: _getMoreData(),
        builder: (BuildContext futureContext, AsyncSnapshot<void> snapShot) {
          return snapShot.connectionState != ConnectionState.done
              ? Container(
                  color: Colors.white.withOpacity(0.7),
                  padding: const EdgeInsets.all(16.0),
                  child: const CircularProgressIndicator(),
                )
              : SizedBox.fromSize(size: Size.zero);
        },
      );
    } else {
      return SizedBox.fromSize(size: Size.zero);
    }
  }

  void _setupWindow(double end) {
    nextEnd = end;
    nextStart = nextEnd - windowTime;
    if (nextStart < 0) {
      nextStart = 0;
    }
    hasNextWindow = nextEnd - nextStart > 0;
  }

  Future<void> _getInitialData() async {
    if (!hasNextWindow) {
      return;
    }

    try {
      final Data data = await _getDataUseCase.execute(nextStart, nextEnd);
      _setupWindow(data.points.first.x);

      setState(() {
        _data = data;
      });
    } catch (e) {
      _showException(e);
    }
  }

  Future<void> _getMoreData() async {
    try {
      final Data data = await _getDataUseCase.execute(nextStart, nextEnd);
      if (data.points.isNotEmpty) {
        _setupWindow(data.points.first.x);

        _updateData(data.points);
      } else {
        hasNextWindow = false;
      }
    } catch (e) {
      _showException(e);
    }
  }

  void _updateData(List<Point> points) {
    _data = _data.prepend(points);
    isLoadMoreView = true;

    seriesController?.updateDataSource(
      addedDataIndexes: _getIndexes(points.length),
    );
  }

  List<int> _getIndexes(int prevItems) {
    return List<int>.generate(
      prevItems,
      (int index) => index,
    );
  }

  void _showException(Object error) {
    if (mounted) {
      print(error);
    }
  }

  @override
  void dispose() {
    seriesController = null;
    _data.clear();
    super.dispose();
  }
}

class GetDataUseCase {
  Future<Data> execute(double nextStart, double nextEnd) async {
    print('>>> GET DATA: $nextStart > $nextEnd');
    await Future<void>.delayed(const Duration(seconds: 2));
    const int pointsPerSecond = 1000;
    final double timeWindow = nextEnd - nextStart;
    final int points = (pointsPerSecond * timeWindow).round();
    final double timeStep =
        double.parse((timeWindow / points).toStringAsFixed(4));
    // for 3 seconds
    return Data(
      List<Point>.generate(
        points,
        (int index) => Point(
          nextEnd - timeStep * index,
          Random().nextDouble() *
              Random().nextDouble() *
              50 *
              (Random().nextBool() ? -1 : 1),
        ),
      ).reversed.toList(),
    );
  }
}

class Point {
  const Point(this.x, this.y);

  final double x;
  final double y;

  @override
  String toString() {
    return '{x: $x, y: $y}';
  }
}

class Data {
  const Data(
    this.points, {
    this.newItems = 0,
  });

  Data.zero()
      : points = [],
        newItems = 0;

  final List<Point> points;
  final int newItems;

  Data append(List<Point> points) {
    return Data(
      this.points..addAll(points),
      newItems: points.length,
    );
  }

  Data prepend(List<Point> points) {
    return Data(
      this.points..insertAll(0, points),
      newItems: points.length,
    );
  }

  Data copyWith({
    List<Point>? points,
    double? maxTime,
    int? newItems,
  }) {
    return Data(
      points ?? this.points,
      newItems: newItems ?? this.newItems,
    );
  }

  void clear() {
    points.clear();
  }
}

class ChartXAxis extends NumericAxis {
  ChartXAxis({
    double maximum = 0.001,
    double? zoomPosition,
    double? zoomFactor,
  }) : super(
          title: AxisTitle(
            text: 'time (s)',
          ),
          numberFormat: NumberFormat.decimalPattern(),
          majorGridLines: const MajorGridLines(width: 0),
          zoomPosition: zoomPosition,
          zoomFactor: zoomFactor,
        );
}

class ChartYAxis extends NumericAxis {
  ChartYAxis({
    String title = 'μV',
    bool hideTitle = false,
  }) : super(
          title: AxisTitle(
            text: title,
            textStyle: hideTitle
                ? const TextStyle(
                    fontFamily: 'Segoe UI',
                    fontSize: 15.0,
                    color: Colors.transparent,
                    fontStyle: FontStyle.normal,
                    fontWeight: FontWeight.normal,
                  )
                : null,
          ),
          labelsExtent: 32.0,
          majorGridLines: const MajorGridLines(width: 0.7),
        );
}

class ChartZoomBehavior extends ZoomPanBehavior {
  ChartZoomBehavior()
      : super(
          zoomMode: ZoomMode.x,
          enablePinching: true,
          enablePanning: true,
          enableDoubleTapZooming: true,
          enableMouseWheelZooming: true,
        );
}
