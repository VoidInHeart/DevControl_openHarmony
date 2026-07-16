#include "device_simulator.h"
#include <cmath>
#include <cstdlib>
#include <sstream>

namespace {
double clampValue(double value, double minimum, double maximum)
{
    if (value < minimum) {
        return minimum;
    }
    if (value > maximum) {
        return maximum;
    }
    return value;
}
}

DeviceSimulator& DeviceSimulator::getInstance()
{
    static DeviceSimulator instance;
    return instance;
}

void DeviceSimulator::registerDevice(const std::string& id, const std::string& name, DeviceType type, const std::string& brand)
{
    std::lock_guard<std::mutex> lock(mutex_);
    DeviceInfo info;
    info.id = id;
    info.name = name;
    info.type = type;
    info.brand = brand;
    info.state.online = true;
    info.state.isLocked = true;
    info.state.isOn = false;
    info.state.brightness = 0.0;
    info.state.lastBrightness = 100.0;
    info.state.temperature = 22.0;
    info.state.humidity = 55.0;
    info.state.acPower = false;
    info.state.acMode = 0;
    info.state.targetTemp = 26.0;
    info.state.targetHumidity = 50.0;
    info.state.batteryLevel = 100.0;
    info.autoLockTicksRemaining = 0;
    devices_[id] = info;
}

void DeviceSimulator::removeDevice(const std::string& id)
{
    std::lock_guard<std::mutex> lock(mutex_);
    devices_.erase(id);
}

std::vector<DeviceInfo> DeviceSimulator::listDevices()
{
    std::lock_guard<std::mutex> lock(mutex_);
    std::vector<DeviceInfo> result;
    for (auto& pair : devices_) {
        result.push_back(pair.second);
    }
    return result;
}

DeviceState DeviceSimulator::getDeviceState(const std::string& id)
{
    std::lock_guard<std::mutex> lock(mutex_);
    auto it = devices_.find(id);
    if (it != devices_.end()) {
        return it->second.state;
    }
    DeviceState empty = {};
    empty.online = false;
    return empty;
}

void DeviceSimulator::updateDeviceState(const std::string& id, const DeviceState& state)
{
    std::lock_guard<std::mutex> lock(mutex_);
    auto it = devices_.find(id);
    if (it != devices_.end()) {
        it->second.state = state;
    }
}

std::string DeviceSimulator::simulateCommand(const std::string& deviceId, const std::string& command, const std::string& param)
{
    std::lock_guard<std::mutex> lock(mutex_);
    auto it = devices_.find(deviceId);
    if (it == devices_.end()) {
        return "{\"result\":\"error\",\"message\":\"device not found\"}";
    }

    DeviceInfo& device = it->second;

    if (command == "lock") {
        device.state.isLocked = true;
        device.autoLockTicksRemaining = 0;
        return "{\"result\":\"ok\",\"state\":\"locked\"}";
    } else if (command == "unlock") {
        device.state.isLocked = false;
        device.autoLockTicksRemaining = 5;
        return "{\"result\":\"ok\",\"state\":\"unlocked\"}";
    } else if (command == "turnOn") {
        device.state.isOn = true;
        if (device.type == DEVICE_LIGHT) {
            if (!param.empty()) {
                double val = clampValue(std::atof(param.c_str()), 0.0, 100.0);
                device.state.brightness = val > 0 ? val : device.state.lastBrightness;
            } else {
                device.state.brightness = device.state.lastBrightness > 0 ? device.state.lastBrightness : 100.0;
            }
            device.state.lastBrightness = device.state.brightness;
        } else {
            device.state.brightness = 100.0;
        }
        return "{\"result\":\"ok\",\"state\":\"on\"}";
    } else if (command == "turnOff") {
        if (device.type == DEVICE_LIGHT && device.state.brightness > 0) {
            device.state.lastBrightness = device.state.brightness;
        }
        device.state.isOn = false;
        device.state.brightness = 0.0;
        return "{\"result\":\"ok\",\"state\":\"off\"}";
    } else if (command == "setBrightness") {
        double val = clampValue(std::atof(param.c_str()), 0.0, 100.0);
        device.state.brightness = val;
        if (val > 0) {
            device.state.isOn = true;
            device.state.lastBrightness = val;
        } else {
            device.state.isOn = false;
        }
        return "{\"result\":\"ok\",\"brightness\":" + std::to_string(val) + "}";
    } else if (command == "acPowerOn") {
        device.state.acPower = true;
        return "{\"result\":\"ok\",\"state\":\"on\"}";
    } else if (command == "acPowerOff") {
        device.state.acPower = false;
        return "{\"result\":\"ok\",\"state\":\"off\"}";
    } else if (command == "setTargetTemp") {
        double val = clampValue(std::atof(param.c_str()), 16.0, 30.0);
        device.state.targetTemp = val;
        return "{\"result\":\"ok\",\"targetTemp\":" + std::to_string(val) + "}";
    } else if (command == "setTargetHumidity") {
        double val = clampValue(std::atof(param.c_str()), 20.0, 80.0);
        device.state.targetHumidity = val;
        return "{\"result\":\"ok\",\"targetHumidity\":" + std::to_string(val) + "}";
    } else if (command == "setACMode") {
        int val = std::atoi(param.c_str());
        device.state.acMode = val;
        return "{\"result\":\"ok\",\"mode\":" + param + "}";
    } else if (command == "getStatus") {
        return "{\"result\":\"ok\",\"online\":" + std::string(device.state.online ? "true" : "false") +
               ",\"isLocked\":" + std::string(device.state.isLocked ? "true" : "false") +
               ",\"isOn\":" + std::string(device.state.isOn ? "true" : "false") +
               ",\"brightness\":" + std::to_string(device.state.brightness) +
               ",\"temperature\":" + std::to_string(device.state.temperature) +
               ",\"humidity\":" + std::to_string(device.state.humidity) +
               ",\"acPower\":" + std::string(device.state.acPower ? "true" : "false") +
               ",\"acMode\":" + std::to_string(device.state.acMode) +
               ",\"targetTemp\":" + std::to_string(device.state.targetTemp) +
               ",\"targetHumidity\":" + std::to_string(device.state.targetHumidity) + "}";
    }

    return "{\"result\":\"error\",\"message\":\"unknown command\"}";
}

double DeviceSimulator::simulateTemperature()
{
    double base = 22.0;
    double sinWave = 3.0 * std::sin(tickCount_ * 0.01);
    double noise = ((std::rand() % 100) - 50) * 0.01;
    return base + sinWave + noise;
}

double DeviceSimulator::simulateHumidity()
{
    double base = 55.0;
    double sinWave = 10.0 * std::sin(tickCount_ * 0.008 + 1.5);
    double noise = ((std::rand() % 100) - 50) * 0.04;
    return base + sinWave + noise;
}

void DeviceSimulator::updateSensorData(DeviceInfo& device)
{
    device.state.temperature = simulateTemperature();
    device.state.humidity = simulateHumidity();
}

void DeviceSimulator::updateACEffect(DeviceInfo& device)
{
    if (!device.state.acPower) {
        return;
    }
    double currentTemp = device.state.temperature;
    double target = device.state.targetTemp;
    double diff = target - currentTemp;
    if (std::abs(diff) > 0.1) {
        double step = diff > 0 ? 0.2 : -0.2;
        if (std::abs(diff) < 0.2) {
            step = diff;
        }
        device.state.temperature = currentTemp + step;
    }
    double currentHum = device.state.humidity;
    double targetHum = device.state.targetHumidity;
    double humDiff = targetHum - currentHum;
    if (std::abs(humDiff) > 0.1) {
        double humStep = humDiff > 0 ? 0.3 : -0.3;
        if (std::abs(humDiff) < 0.3) {
            humStep = humDiff;
        }
        device.state.humidity = currentHum + humStep;
    }
}

void DeviceSimulator::tick()
{
    std::lock_guard<std::mutex> lock(mutex_);
    tickCount_++;
    for (auto& pair : devices_) {
        DeviceInfo& device = pair.second;
        if (device.type == DEVICE_SENSOR) {
            updateSensorData(device);
        } else if (device.type == DEVICE_AC) {
            updateSensorData(device);
            updateACEffect(device);
        } else if (device.type == DEVICE_DOOR) {
            if (!device.state.isLocked && device.autoLockTicksRemaining > 0) {
                device.autoLockTicksRemaining--;
                if (device.autoLockTicksRemaining == 0) {
                    device.state.isLocked = true;
                }
            }
            if (device.state.batteryLevel > 0 && tickCount_ % 60 == 0) {
                device.state.batteryLevel -= 0.1;
                if (device.state.batteryLevel < 0) {
                    device.state.batteryLevel = 0;
                }
            }
        }
    }
}

void DeviceSimulator::initDefaultDevices()
{
    registerDevice("door_001", "Front Door", DEVICE_DOOR, "");
    registerDevice("door_002", "Back Door", DEVICE_DOOR, "");
    registerDevice("light_001", "Living Room Light", DEVICE_LIGHT, "");
    registerDevice("light_002", "Bedroom Light", DEVICE_LIGHT, "");
    registerDevice("light_003", "Kitchen Light", DEVICE_LIGHT, "");
    registerDevice("sensor_001", "Living Room Sensor", DEVICE_SENSOR, "");
    registerDevice("sensor_002", "Bedroom Sensor", DEVICE_SENSOR, "");
    registerDevice("ac_001", "Living Room AC", DEVICE_AC, "haier");
    registerDevice("ac_002", "Bedroom AC", DEVICE_AC, "gree");
}
