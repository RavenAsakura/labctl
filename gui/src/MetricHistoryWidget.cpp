#include "MetricHistoryWidget.hpp"

#include <QPainter>
#include <QPainterPath>
#include <algorithm>

MetricHistoryWidget::MetricHistoryWidget(
    const QString& title,
    const QString& unit,
    int maximumPoints,
    QWidget* parent)
    : QWidget(parent),
      title_(title),
      unit_(unit),
      maximumPoints_(std::max(2, maximumPoints))
{
    setObjectName(QStringLiteral("historyChart"));
    setMinimumHeight(105);
}

void MetricHistoryWidget::addSample(double value)
{
    samples_.append(value);
    while (samples_.size() > maximumPoints_) {
        samples_.removeFirst();
    }
    update();
}

int MetricHistoryWidget::sampleCount() const
{
    return samples_.size();
}

void MetricHistoryWidget::paintEvent(QPaintEvent* event)
{
    QWidget::paintEvent(event);

    QPainter painter(this);
    painter.setRenderHint(QPainter::Antialiasing);

    painter.setPen(QColor(QStringLiteral("#cbd5e1")));
    painter.drawText(QRectF(12, 8, width() - 24, 20), title_);

    if (samples_.isEmpty()) {
        painter.setPen(QColor(QStringLiteral("#64748b")));
        painter.drawText(rect(), Qt::AlignCenter, QStringLiteral("Waiting for data"));
        return;
    }

    painter.setPen(QColor(QStringLiteral("#60a5fa")));
    painter.drawText(
        QRectF(12, 8, width() - 24, 20),
        Qt::AlignRight,
        QStringLiteral("%1 %2").arg(samples_.constLast(), 0, 'f', 1).arg(unit_)
    );

    const QRectF graph(12, 36, width() - 24, height() - 48);
    painter.setPen(QPen(QColor(QStringLiteral("#334155")), 1));
    painter.drawLine(graph.bottomLeft(), graph.bottomRight());
    painter.drawLine(graph.topLeft(), graph.topRight());

    const auto [minimumIterator, maximumIterator] =
        std::minmax_element(samples_.cbegin(), samples_.cend());
    double minimum = *minimumIterator;
    double maximum = *maximumIterator;
    if (maximum - minimum < 1.0) {
        maximum = minimum + 1.0;
    }

    QPainterPath path;
    const int denominator = std::max(
        1,
        static_cast<int>(samples_.size()) - 1
    );
    for (int index = 0; index < samples_.size(); ++index) {
        const double x = graph.left() +
            graph.width() * index / denominator;
        const double normalized = (samples_.at(index) - minimum) / (maximum - minimum);
        const double y = graph.bottom() - normalized * graph.height();
        if (index == 0) {
            path.moveTo(x, y);
        } else {
            path.lineTo(x, y);
        }
    }

    painter.setPen(QPen(QColor(QStringLiteral("#3b82f6")), 2));
    painter.drawPath(path);
}
