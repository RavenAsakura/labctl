add_test(
    NAME labctl-cli-tests
    COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/../../tests/test_cli.sh"
)

add_test(
    NAME labctl-profile-tests
    COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/../../tests/test_profile.sh"
)

add_test(
    NAME labctl-policykit-tests
    COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/../../tests/test_privilege.sh"
)

qt_add_executable(
    labctl-gui-tests
    MainWindowTest.cpp
    ../src/MainWindow.cpp
    ../src/LabctlRunner.cpp
    ../src/MetricHistoryWidget.cpp
    ../include/MainWindow.hpp
    ../include/LabctlRunner.hpp
    ../include/MetricHistoryWidget.hpp
)

target_include_directories(
    labctl-gui-tests
    PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/../include"
)

target_link_libraries(
    labctl-gui-tests
    PRIVATE
        Qt6::Core
        Qt6::Gui
        Qt6::Test
        Qt6::Widgets
)

target_compile_options(
    labctl-gui-tests
    PRIVATE
        -Wall
        -Wextra
        -Wpedantic
)

add_test(NAME labctl-gui-navigation COMMAND labctl-gui-tests)
set_tests_properties(
    labctl-gui-navigation
    PROPERTIES
        ENVIRONMENT
            "QT_QPA_PLATFORM=offscreen;LABCTL_GUI_DISABLE_AUTO_REFRESH=1;LABCTL_CLI=${CMAKE_CURRENT_SOURCE_DIR}/../../labctl"
)
