#pragma once

#include <QVector>
#include <QWidget>

class MetricHistoryWidget final : public QWidget
{
    Q_OBJECT

public:
    explicit MetricHistoryWidget(
        const QString& title,
        const QString& unit,
        int maximumPoints = 30,
        QWidget* parent = nullptr
    );

    void addSample(double value);
    int sampleCount() const;

protected:
    void paintEvent(QPaintEvent* event) override;

private:
    QString title_;
    QString unit_;
    QVector<double> samples_;
    int maximumPoints_;
};
