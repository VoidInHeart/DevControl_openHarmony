#ifndef DEVICE_SIMULATOR_H
#define DEVICE_SIMULATOR_H

#include <string>
#include <vector>
#include <map>
#include <mutex>

enum DeviceType {
    DEVICE_DOOR = 0,
    DEVICE_LIGHT = 1,
    DEVICE_SENSOR = 2,
    DEVICE_AC = 3
};

struct DeviceState {
    bool online;
    bool isLocked;
    bool isOn;
    double brightness;
    double lastBrightness;
    double temperature;
    double humidity;
    bool acPower;
    int acMode;
    double targetTemp;
    double targetHumidity;
    double batteryLevel;
};

struct DeviceInfo {
    std::string id;
    std::string name;
    DeviceType type;
    std::string brand;
    DeviceState state;
    int autoLockTicksRemaining;
};

class DeviceSimulator {
public:
    static DeviceSimulator& getInstance();

    void registerDevice(const std::string& id, const std::string& name, DeviceType type, const std::string& brand);
    void removeDevice(const std::string& id);
    std::vector<DeviceInfo> listDevices();
    DeviceState getDeviceState(const std::string& id);
    void updateDeviceState(const std::string& id, const DeviceState& state);

    std::string simulateCommand(const std::string& deviceId, const std::string& command, const std::string& param);

    void tick();

    void initDefaultDevices();

private:
    DeviceSimulator() = default;
    std::map<std::string, DeviceInfo> devices_;
    std::mutex mutex_;
    int64_t tickCount_ = 0;

    double simulateTemperature();
    double simulateHumidity();
    void updateSensorData(DeviceInfo& device);
    void updateACEffect(DeviceInfo& device);
};

#endif
