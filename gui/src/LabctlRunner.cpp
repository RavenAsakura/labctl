#include "LabctlRunner.hpp"

#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QProcessEnvironment>
#include <QStandardPaths>

LabctlRunner::LabctlRunner(QObject* parent)
    : QObject(parent),
      executablePath_(locateExecutable())
{
    process_.setProcessChannelMode(QProcess::SeparateChannels);

    connect(
        &process_,
        &QProcess::readyReadStandardOutput,
        this,
        [this]()
        {
            const QString output =
                QString::fromUtf8(process_.readAllStandardOutput());

            if (!output.isEmpty()) {
                emit standardOutputReceived(output);
            }
        }
    );

    connect(
        &process_,
        &QProcess::readyReadStandardError,
        this,
        [this]()
        {
            const QString error =
                QString::fromUtf8(process_.readAllStandardError());

            if (!error.isEmpty()) {
                emit standardErrorReceived(error);
            }
        }
    );

    connect(
        &process_,
        qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
        this,
        &LabctlRunner::commandFinished
    );

    connect(
        &process_,
        &QProcess::errorOccurred,
        this,
        [this](QProcess::ProcessError)
        {
            emit runnerError(process_.errorString());
        }
    );
}

QString LabctlRunner::executablePath() const
{
    return executablePath_;
}

bool LabctlRunner::isRunning() const
{
    return process_.state() != QProcess::NotRunning;
}

void LabctlRunner::run(
    const QStringList& arguments,
    bool usePolicyKit)
{
    if (isRunning()) {
        emit runnerError(
            QStringLiteral("A LabCTL command is already running.")
        );
        return;
    }

    if (executablePath_.isEmpty()) {
        executablePath_ = locateExecutable();
    }

    if (executablePath_.isEmpty()) {
        emit runnerError(
            QStringLiteral(
                "The LabCTL CLI executable could not be found. "
                "Set LABCTL_CLI or ensure the repository executable exists."
            )
        );
        return;
    }

    const QString command =
        executablePath_ + QLatin1Char(' ') + arguments.join(QLatin1Char(' '));

    emit commandStarted(command);

    QProcessEnvironment environment =
        QProcessEnvironment::systemEnvironment();

    environment.insert(QStringLiteral("NO_COLOR"), QStringLiteral("1"));

    if (usePolicyKit) {
        environment.insert(
            QStringLiteral("LABCTL_USE_PKEXEC"),
            QStringLiteral("1")
        );
    } else {
        environment.remove(QStringLiteral("LABCTL_USE_PKEXEC"));
    }

    process_.setProcessEnvironment(environment);
    process_.setProgram(executablePath_);
    process_.setArguments(arguments);
    process_.start();
}

void LabctlRunner::stop()
{
    if (!isRunning()) {
        return;
    }

    process_.terminate();

    if (!process_.waitForFinished(2000)) {
        process_.kill();
    }
}

QString LabctlRunner::locateExecutable() const
{
    const QString configuredPath =
        QProcessEnvironment::systemEnvironment()
            .value(QStringLiteral("LABCTL_CLI"));

    if (!configuredPath.isEmpty()) {
        const QFileInfo configuredFile(configuredPath);

        if (configuredFile.exists() && configuredFile.isExecutable()) {
            return configuredFile.absoluteFilePath();
        }
    }

    const QString pathExecutable =
        QStandardPaths::findExecutable(QStringLiteral("labctl"));

    if (!pathExecutable.isEmpty()) {
        return pathExecutable;
    }

    const QDir applicationDirectory(
        QCoreApplication::applicationDirPath()
    );

    const QStringList candidates = {
        applicationDirectory.absoluteFilePath(
            QStringLiteral("../../labctl")
        ),
        applicationDirectory.absoluteFilePath(
            QStringLiteral("../../../labctl")
        ),
        QDir::current().absoluteFilePath(
            QStringLiteral("../labctl")
        ),
        QDir::current().absoluteFilePath(
            QStringLiteral("../../labctl")
        )
    };

    for (const QString& candidate : candidates) {
        const QFileInfo file(candidate);

        if (file.exists() && file.isFile() && file.isExecutable()) {
            return file.absoluteFilePath();
        }
    }

    return {};
}
