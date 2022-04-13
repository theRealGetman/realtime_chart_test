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
            LinearProgressIndicator(),
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

  late GetDataStreamUseCase _getDataStreamUseCase;
  StreamSubscription<Data>? _dataSubscription;

  @override
  void initState() {
    super.initState();

    _zoomPanBehavior = ChartZoomBehavior();
    _getDataStreamUseCase = GetDataStreamUseCase();
    _getData();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 400.0,
          child: _buildInfiniteScrollingChart(),
        ),
      ],
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
    );
  }

  List<ChartSeries<Point, double>> getSeries() {
    return <ChartSeries<Point, double>>[
      FastLineSeries<Point, double>(
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
      // Logger().i('changed: ${args.actualMin} : ${args.actualMax}');
      if (isLoadMoreView) {
        args.visibleMin = oldAxisVisibleMin;
        args.visibleMax = oldAxisVisibleMax;
      }
      oldAxisVisibleMax =
          double.parse((args.actualMax as num).toStringAsFixed(3));
      oldAxisVisibleMin = oldAxisVisibleMax! > loadInterval * 2
          ? oldAxisVisibleMax! - loadInterval * 2
          : oldAxisVisibleMax! - loadInterval;
    }
    isLoadMoreView = false;
  }

  Future<void> _getData() async {
    try {
      _dataSubscription?.cancel();

      _dataSubscription = _getDataStreamUseCase.execute().listen(
        (Data data) {
          if (mounted) {
            if (_data.points.isEmpty) {
              setState(() {
                _data = data;
              });
            } else {
              _updateData(data.points);
            }
          }
        },
        onError: (Object e) {
          _showException(e);
        },
      );
    } catch (e) {
      _showException(e);
    }
  }

  void _updateData(List<Point> points) {
    _data = _data.append(points);
    isLoadMoreView = true;
    seriesController?.updateDataSource(
      addedDataIndexes: _getIndexes(
        _data.points.length,
        _data.newItems,
      ),
    );
    // this zoomIn fixes actual range update in some cases
    // _zoomPanBehavior.zoomIn();
  }

  List<int> _getIndexes(int total, int newItems) {
    final List<int> indexes = <int>[];
    for (int i = newItems - 1; i >= 0; i--) {
      indexes.add(total - 1 - i);
    }
    return indexes;
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
    _dataSubscription?.cancel();
    _dataSubscription = null;
    super.dispose();
  }
}

class GetDataStreamUseCase {
  Stream<Data> execute() async* {
    // 100 iterations for 300 millis each => 30 sec
    for (int i = 0; i <= 100; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      // 2000 points for each iteration
      yield Data(
        List<Point>.generate(
          2000,
          (int index) => Point(
            i * 0.3 + 0.00015 * index,
            Random().nextDouble() *
                Random().nextDouble() *
                150 *
                (Random().nextBool() ? -1 : 1),
          ),
        ),
      );
    }
  }
}

class Point {
  const Point(this.x, this.y);

  final double x;
  final double y;
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
