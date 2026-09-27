#include "MainWindow.hpp"
#include "MetricHistoryWidget.hpp"

#include <QFrame>
#include <QCheckBox>
#include <QLabel>
#include <QPushButton>
#include <QStackedWidget>
#include <QTreeWidget>
#include <QtTest>

class MainWindowTest final : public QObject
{
    Q_OBJECT

private slots:
    void exposesFunctionalPages();
    void providesServiceControls();
    void providesOperationalDashboard();
    void populatesDashboardMetrics();
};

void MainWindowTest::exposesFunctionalPages()
{
    MainWindow window;

    auto* stack = window.findChild<QStackedWidget*>(
        QStringLiteral("pageStack")
    );
    QVERIFY(stack != nullptr);
    QCOMPARE(stack->count(), 8);

    const QList<QPushButton*> navigation =
        window.findChildren<QPushButton*>(QStringLiteral("navigationButton"));
    QCOMPARE(navigation.size(), 8);

    QPushButton* settingsButton = nullptr;

    for (QPushButton* button : navigation) {
        if (button->property("page").toString() == QStringLiteral("Settings")) {
            settingsButton = button;
            break;
        }
    }

    QVERIFY(settingsButton != nullptr);
    settingsButton->click();
    QCOMPARE(stack->currentIndex(), 7);
}

void MainWindowTest::providesServiceControls()
{
    MainWindow window;

    const QList<QPushButton*> actions =
        window.findChildren<QPushButton*>(QStringLiteral("actionButton"));

    QCOMPARE(actions.size(), 20);

    for (QPushButton* button : actions) {
        QVERIFY(!button->property("module").toString().isEmpty());
        QVERIFY(!button->property("action").toString().isEmpty());
    }

    QVERIFY(
        window.findChild<QPushButton*>(QStringLiteral("secondaryButton"))
        != nullptr
    );
}

void MainWindowTest::providesOperationalDashboard()
{
    MainWindow window;

    QCOMPARE(
        window.findChildren<QFrame*>(QStringLiteral("metricCard")).size(),
        4
    );
    QCOMPARE(
        window.findChildren<QPushButton*>(QStringLiteral("profileButton")).size(),
        2
    );
    QVERIFY(
        window.findChild<QFrame*>(QStringLiteral("alertsPanel")) != nullptr
    );
    QVERIFY(
        window.findChild<QStackedWidget*>(QStringLiteral("pageStack"))
        != nullptr
    );
    QVERIFY(
        window.findChild<QCheckBox*>(QStringLiteral("autoRefreshCheck"))
        != nullptr
    );
    QCOMPARE(
        window.findChildren<MetricHistoryWidget*>(QStringLiteral("historyChart")).size(),
        4
    );
    QVERIFY(
        window.findChild<QTreeWidget*>(QStringLiteral("workloadsTree"))
        != nullptr
    );
}

void MainWindowTest::populatesDashboardMetrics()
{
    qunsetenv("LABCTL_GUI_DISABLE_AUTO_REFRESH");
    MainWindow window;

    QLabel* cpuMetric = nullptr;
    const QList<QLabel*> labels = window.findChildren<QLabel*>();

    for (QLabel* label : labels) {
        if (label->property("dashboardMetric").toString()
            == QStringLiteral("cpu")) {
            cpuMetric = label;
            break;
        }
    }

    QVERIFY(cpuMetric != nullptr);
    QTRY_VERIFY_WITH_TIMEOUT(cpuMetric->text() != QStringLiteral("--"), 5000);
    QVERIFY(cpuMetric->text().contains(QLatin1Char('%')));
    QVERIFY(cpuMetric->text().contains(QStringLiteral("°C")));

    auto* cpuHistory = window.findChild<MetricHistoryWidget*>(
        QStringLiteral("historyChart")
    );
    QVERIFY(cpuHistory != nullptr);
    QVERIFY(cpuHistory->sampleCount() >= 1);

    qputenv("LABCTL_GUI_DISABLE_AUTO_REFRESH", "1");
}

QTEST_MAIN(MainWindowTest)

#include "MainWindowTest.moc"
