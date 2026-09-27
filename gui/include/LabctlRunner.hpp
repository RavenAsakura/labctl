#pragma once

#include <QObject>
#include <QProcess>
#include <QString>
#include <QStringList>

class LabctlRunner final : public QObject
{
    Q_OBJECT

public:
    explicit LabctlRunner(QObject* parent = nullptr);

    [[nodiscard]] QString executablePath() const;
    [[nodiscard]] bool isRunning() const;

public slots:
    void run(const QStringList& arguments, bool usePolicyKit = false);
    void stop();

signals:
    void commandStarted(const QString& command);
    void standardOutputReceived(const QString& output);
    void standardErrorReceived(const QString& error);
    void commandFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void runnerError(const QString& message);

private:
    [[nodiscard]] QString locateExecutable() const;

    QProcess process_;
    QString executablePath_;
};
