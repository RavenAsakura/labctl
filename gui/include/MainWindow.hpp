#pragma once

#include <QMainWindow>
#include <QHash>
#include <QString>
#include <QStringList>

class QLabel;
class QFrame;
class QCheckBox;
class QPlainTextEdit;
class QPushButton;
class QStackedWidget;
class QTimer;
class QTreeWidget;
class QWidget;
class LabctlRunner;
class MetricHistoryWidget;

class MainWindow final : public QMainWindow
{
    Q_OBJECT

public:
    explicit MainWindow(QWidget* parent = nullptr);
    ~MainWindow() override;

private:
    enum class ActiveCommand
    {
        None,
        Dashboard,
        OneDrive,
        Profile,
        Generic
    };

    void buildInterface();
    void configureRunner();

    void refreshDashboard();
    void refreshCurrentPage();
    void runOneDriveStatus();
    void showPage(const QString& page);
    void runCommand(
        const QStringList& arguments,
        bool usePolicyKit = false,
        ActiveCommand commandType = ActiveCommand::Generic
    );
    void runServiceAction(
        const QString& module,
        const QString& action,
        const QString& serviceName
    );
    void runProfileAction(const QString& profile);
    QWidget* createCommandPage(
        const QString& description,
        QPlainTextEdit*& output
    );
    QWidget* createServicesPage(QPlainTextEdit*& output);
    QWidget* createWorkloadsPage(QPlainTextEdit*& output);
    void setControlsBusy(bool busy);

    void parseDashboardOutput(const QString& output);
    void parseOneDriveOutput(const QString& output);

    static QString capturedValue(
        const QString& output,
        const QString& pattern
    );

    static void setServiceStatus(
        QLabel* label,
        const QString& status
    );

    QLabel* pageTitleLabel_{};
    QLabel* pageSubtitleLabel_{};
    QLabel* healthBadgeLabel_{};

    QLabel* cpuValueLabel_{};
    QLabel* memoryValueLabel_{};
    QLabel* gpuValueLabel_{};
    QLabel* batteryValueLabel_{};
    QLabel* storageValueLabel_{};
    QLabel* profileValueLabel_{};
    QLabel* powerValueLabel_{};
    QLabel* networkValueLabel_{};
    QLabel* ipValueLabel_{};
    QLabel* vpnValueLabel_{};
    QLabel* containersValueLabel_{};
    QLabel* libvirtVmValueLabel_{};
    QLabel* vmwareVmValueLabel_{};
    QLabel* virtualboxVmValueLabel_{};
    QLabel* alertsLabel_{};
    QLabel* lastUpdatedLabel_{};

    QLabel* dockerStatusLabel_{};
    QLabel* vmwareStatusLabel_{};
    QLabel* libvirtStatusLabel_{};
    QLabel* oneDriveStatusLabel_{};
    QLabel* ollamaStatusLabel_{};

    QPlainTextEdit* commandOutput_{};
    QPushButton* refreshButton_{};
    QPushButton* cancelButton_{};
    QPushButton* detailsButton_{};
    QCheckBox* autoRefreshCheck_{};
    QFrame* dashboardOutputPanel_{};
    QStackedWidget* pageStack_{};
    QTimer* dashboardRefreshTimer_{};
    QTreeWidget* workloadsTree_{};
    MetricHistoryWidget* cpuHistory_{};
    MetricHistoryWidget* memoryHistory_{};
    MetricHistoryWidget* temperatureHistory_{};
    MetricHistoryWidget* networkHistory_{};

    LabctlRunner* labctlRunner_{};

    ActiveCommand activeCommand_{ActiveCommand::None};
    QString currentPage_{QStringLiteral("Dashboard")};
    QHash<QString, int> pageIndexes_;
    QHash<QString, QPlainTextEdit*> pageOutputs_;
    bool cancellationRequested_{false};
    QString dashboardHealth_{QStringLiteral("UNKNOWN")};
    QString outputBuffer_;
};
