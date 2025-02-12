import 'dart:math';

import 'package:flutter/material.dart'
    show Color, TextStyle, Rect, Canvas, Size, CustomPainter;
import 'package:technixo_k_chart_v2/utils/date_format_util.dart';
import 'package:technixo_k_chart_v2/utils/n_interval.dart';
import 'package:technixo_k_chart_v2/utils/number_util.dart';

import '../chart_style.dart' show ChartStyle;
import '../entity/k_line_entity.dart';

export 'package:flutter/material.dart'
    show Color, required, TextStyle, Rect, Canvas, Size, CustomPainter;

abstract class BaseChartPainter extends CustomPainter {
  final String text;
  final TextStyle textStyle;
  static double maxScrollX = 0.0;
  List<KLineEntity> datas;
  MainState mainState;
  bool volHidden;
  SecondaryState secondaryState;

  double scaleX = 1.0, scrollX = 0.0, selectX;
  bool isLongPress = false;
  bool isLine;

  //3块区域大小与位置
  late Rect mMainRect;
  Rect? mVolRect, mSecondaryRect;
  late double mDisplayHeight, mWidth;

  int mStartIndex = 0, mStopIndex = 0;
  double mMainMaxValue = -double.maxFinite, mMainMinValue = double.maxFinite;
  double mVolMaxValue = -double.maxFinite, mVolMinValue = double.maxFinite;
  double mSecondaryMaxValue = -double.maxFinite,
      mSecondaryMinValue = double.maxFinite;
  double mTranslateX = -double.maxFinite;
  int mMainMaxIndex = 0, mMainMinIndex = 0;
  double mMainHighMaxValue = -double.maxFinite,
      mMainLowMinValue = double.maxFinite;
  int mItemCount = 0;
  double mDataLen = 0.0; //数据占屏幕总长度
  late double mPointWidth;
  List<String> mFormats = [yyyy, '-', mm, '-', dd, ' ', HH, ':', nn]; //格式化时间
  double mMarginRight = 0.0; //k线右边空出来的距离

  final ChartStyle chartStyle;

  BaseChartPainter(
    this.chartStyle, {
    required this.datas,
    required this.scaleX,
    required this.scrollX,
    required this.isLongPress,
    required this.selectX,
    required this.text,
    required this.textStyle,
    this.mainState = MainState.MA,
    this.volHidden = false,
    this.secondaryState = SecondaryState.MACD,
    this.isLine = false,
  }) {
    mPointWidth = chartStyle.pointWidth;
    mItemCount = datas.length;
    mDataLen = mItemCount * mPointWidth;
    initFormats();
  }

  void initFormats() {
//    [yyyy, '-', mm, '-', dd, ' ', HH, ':', nn]
    if (mItemCount < 2) return;
    int firstTime = datas.first.id ?? 0;
    int secondTime = datas[1].id ?? 0;
    int time = secondTime - firstTime;
    //月线
    if (time >= 24 * 60 * 60 * 28)
      mFormats = [yy, '-', mm];
    //日线等
    else if (time >= 24 * 60 * 60)
      mFormats = [yy, '-', mm, '-', dd];
    //小时线等
    else
      mFormats = [mm, '-', dd, ' ', HH, ':', nn];
    // mFormats = [HH, ':', nn];
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Rect.fromLTRB(0, 0, size.width, size.height));
    mDisplayHeight =
        size.height - chartStyle.topPadding - chartStyle.bottomDateHigh;
    mWidth = size.width;
    mMarginRight = (mWidth / chartStyle.gridColumns - mPointWidth) / scaleX;
    initRect(size);
    calculateValue();
    initChartRenderer();

    canvas.save();
    canvas.scale(1, 1);
    drawBg(canvas, size);
    drawGrid(canvas);
    if (text.isNotEmpty) {
      drawLabel(canvas, size);
    }
    if (datas.isNotEmpty) {
      drawChart(canvas, size);
      drawRightText(canvas);
      drawRealTimePrice(canvas, size);
      drawDate(canvas, size);
      if (isLongPress == true) drawCrossLineText(canvas, size);
      drawText(canvas, datas.last, 5);
      drawMaxAndMin(canvas);
    }
    canvas.restore();
  }

  void initChartRenderer();

  //draw
  void drawLabel(Canvas canvas, Size size);

  //画背景
  void drawBg(Canvas canvas, Size size);

  //画网格
  void drawGrid(canvas);

  //画图表
  void drawChart(Canvas canvas, Size size);

  //画右边值
  void drawRightText(canvas);

  //画时间
  void drawDate(Canvas canvas, Size size);

  //画值
  void drawText(Canvas canvas, KLineEntity data, double x);

  //画最大最小值
  void drawMaxAndMin(Canvas canvas);

  //交叉线值
  void drawCrossLineText(Canvas canvas, Size size);

  void initRect(Size size) {
    double mainHeight = mDisplayHeight * 0.6;
    double volHeight = mDisplayHeight * 0.2;
    double secondaryHeight = mDisplayHeight * 0.2;
    if (volHidden && secondaryState == SecondaryState.NONE) {
      mainHeight = mDisplayHeight;
    } else if (volHidden || secondaryState == SecondaryState.NONE) {
      mainHeight = mDisplayHeight * 0.8;
    }
    mMainRect = Rect.fromLTRB(
        0, chartStyle.topPadding, mWidth, chartStyle.topPadding + mainHeight);
    if (!volHidden) {
      mVolRect = Rect.fromLTRB(0, mMainRect.bottom + chartStyle.childPadding,
          mWidth, mMainRect.bottom + volHeight);
    }
    if (secondaryState != SecondaryState.NONE) {
      mSecondaryRect = Rect.fromLTRB(
          0,
          (mVolRect?.bottom ?? mMainRect.bottom) + chartStyle.childPadding,
          mWidth,
          (mVolRect?.bottom ?? mMainRect.bottom) + secondaryHeight);
    }
  }

  calculateValue() {
    if (datas.isEmpty) return;
    maxScrollX = getMinTranslateX().abs();
    setTranslateXFromScrollX(scrollX);
    mStartIndex = indexOfTranslateX(xToTranslateX(0));
    mStopIndex = indexOfTranslateX(xToTranslateX(mWidth));
    for (int i = mStartIndex; i <= mStopIndex; i++) {
      var item = datas[i];
      getMainMaxMinValue(item, i);
      getVolMaxMinValue(item);
      getSecondaryMaxMinValue(item);
    }
  }

  void getMainMaxMinValue(KLineEntity item, int i) {
    if (isLine == true) {
      mMainMaxValue = max(mMainMaxValue, item.close);
      mMainMinValue = min(mMainMinValue, item.close);
    } else {
      double maxPrice = item.high, minPrice = item.low;
      if (mainState == MainState.MA) {
        maxPrice = max(item.high, _findMax(item.maValueList ?? [0]));
        minPrice = min(item.low, _findMin(item.maValueList ?? [0]));
      } else if (mainState == MainState.EMA) {
        maxPrice = max(item.high, _findMax(item.emaValueList ?? [0]));
        minPrice = min(item.low, _findMin(item.emaValueList ?? [0]));
      } else if (mainState == MainState.BOLL) {
        maxPrice = max(item.up ?? 0, item.high);
        minPrice = min(item.dn ?? 0, item.low);
      }
      mMainMaxValue = max(mMainMaxValue, maxPrice);
      mMainMinValue = min(mMainMinValue, minPrice);

      if (mMainHighMaxValue < item.high) {
        mMainHighMaxValue = item.high;
        mMainMaxIndex = i;
      }
      if (mMainLowMinValue > item.low) {
        mMainLowMinValue = item.low;
        mMainMinIndex = i;
      }
    }
  }

  double _findMax(List<double> a) {
    return a.reduce((value, element) => max(value, element));
  }

  double _findMin(List<double> a) {
    return a.reduce((value, element) => min(value, element));
  }

  void getVolMaxMinValue(KLineEntity item) {
    mVolMaxValue = max(
        mVolMaxValue, max(item.vol, max(item.MA5Volume!, item.MA10Volume!)));
    mVolMinValue = min(
        mVolMinValue, min(item.vol, min(item.MA5Volume!, item.MA10Volume!)));
  }

  void getSecondaryMaxMinValue(KLineEntity item) {
    if (secondaryState == SecondaryState.MACD) {
      mSecondaryMaxValue =
          max(mSecondaryMaxValue, max(item.macd!, max(item.dif!, item.dea!)));
      mSecondaryMinValue =
          min(mSecondaryMinValue, min(item.macd!, min(item.dif!, item.dea!)));
    } else if (secondaryState == SecondaryState.KDJ) {
      mSecondaryMaxValue =
          max(mSecondaryMaxValue, max(item.k!, max(item.d!, item.j!)));
      mSecondaryMinValue =
          min(mSecondaryMinValue, min(item.k!, min(item.d!, item.j!)));
    } else if (secondaryState == SecondaryState.RSI) {
      mSecondaryMaxValue = max(mSecondaryMaxValue, item.rsi!);
      mSecondaryMinValue = min(mSecondaryMinValue, item.rsi!);
    } else if (secondaryState == SecondaryState.CCI) {
      if (item.cci != null) {
        mSecondaryMaxValue = max(mSecondaryMaxValue, item.cci!);
        mSecondaryMinValue = min(mSecondaryMinValue, item.cci!);
      }
    } else {
      mSecondaryMaxValue = max(mSecondaryMaxValue, item.r!);
      mSecondaryMinValue = min(mSecondaryMinValue, item.r!);
    }
  }

  double xToTranslateX(double x) => -mTranslateX + x / scaleX;

  int indexOfTranslateX(double translateX) =>
      _indexOfTranslateX(translateX, 0, mItemCount - 1);

  ///二分查找当前值的index
  int _indexOfTranslateX(double translateX, int start, int end) {
    if (end == start || end == -1) {
      return start;
    }
    if (end - start == 1) {
      double startValue = getX(start);
      double endValue = getX(end);
      return (translateX - startValue).abs() < (translateX - endValue).abs()
          ? start
          : end;
    }
    int mid = start + (end - start) ~/ 2;
    double midValue = getX(mid);
    if (translateX < midValue) {
      return _indexOfTranslateX(translateX, start, mid);
    } else if (translateX > midValue) {
      return _indexOfTranslateX(translateX, mid, end);
    } else {
      return mid;
    }
  }

  ///根据索引索取x坐标
  ///+ mPointWidth / 2防止第一根和最后一根k线显示不全
  ///@param position 索引值
  double getX(int position) => position * mPointWidth + mPointWidth / 2;

  KLineEntity getItem(int position) {
    return datas[position];
  }

  ///scrollX 转换为 TranslateX
  void setTranslateXFromScrollX(double scrollX) =>
      mTranslateX = scrollX + getMinTranslateX();

  ///获取平移的最小值
  double getMinTranslateX() {
//    var x = -mDataLen + mWidth / scaleX - mPointWidth / 2;
    var x = -mDataLen + mWidth / scaleX - mPointWidth / 2;
    x = x >= 0 ? 0.0 : x;
    //数据不足一屏
    if (x >= 0) {
      if (mWidth / scaleX - getX(datas.length) < mMarginRight) {
        //数据填充后剩余空间比mMarginRight小，求出差。x-=差
        x -= mMarginRight - mWidth / scaleX + getX(datas.length);
      } else {
        //数据填充后剩余空间比Right大
        mMarginRight = mWidth / scaleX - getX(datas.length);
      }
    } else if (x < 0) {
      //数据超过一屏
      x -= mMarginRight;
    }
    return x >= 0 ? 0.0 : x;
  }

  ///计算长按后x的值，转换为index
  int calculateSelectedX(double selectX) {
    int mSelectedIndex = indexOfTranslateX(xToTranslateX(selectX));
    if (mSelectedIndex < mStartIndex) {
      mSelectedIndex = mStartIndex;
    }
    if (mSelectedIndex > mStopIndex) {
      mSelectedIndex = mStopIndex;
    }
    return mSelectedIndex;
  }

  ///translateX转化为view中的x
  double translateXtoX(double translateX) =>
      (translateX + mTranslateX) * scaleX;

  TextStyle getTextStyle(Color color) {
    return TextStyle(fontSize: chartStyle.defaultTextSize, color: color);
  }

  void drawRealTimePrice(Canvas canvas, Size size);

  String format(double n) {
    return NumberUtil.format(n);
  }

  @override
  bool shouldRepaint(BaseChartPainter oldDelegate) {
    return true;
//    return oldDelegate.datas != datas ||
//        oldDelegate.datas?.length != datas?.length ||
//        oldDelegate.scaleX != scaleX ||
//        oldDelegate.scrollX != scrollX ||
//        oldDelegate.isLongPress != isLongPress ||
//        oldDelegate.selectX != selectX ||
//        oldDelegate.isLine != isLine ||
//        oldDelegate.mainState != mainState ||
//        oldDelegate.secondaryState != secondaryState;
  }
}
