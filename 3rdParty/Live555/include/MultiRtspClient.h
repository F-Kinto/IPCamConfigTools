#pragma once

#include <functional>
#include <future>
#include <memory>
#include <string>

class MultiRtspClient {
public:
	using string = std::string;
	// param:buffer,bufferSize,type:video or audio,codecName,index,rtsp url,custom clientData
	using rtspDataCallBack = std::function<void(unsigned char*, int, const char*, const char*, int, char*, void*)>;

	// PIMPL
	struct Impl;

	MultiRtspClient();
	~MultiRtspClient();

	bool insertRtspUrl(const string& url);
	bool insertRtspUrl(const string& url, int userIndex);
	
	// Set custom context pointer passed to callback.
	// IMPORTANT: Caller must ensure 'obj' remains valid until startOpenUrl() returns.
	// The pointer is NOT owned or managed by MultiRtspClient.
	void setCustomObj(void* obj);
	
	void setRtpOverTcp(const bool& isTrue);
	void setRtspDataCallBack(const rtspDataCallBack& callBack);

	// Blocking call: runs until isQuit becomes ready or stream ends.
	bool startOpenUrl(const std::shared_future<bool>& isQuit);

private:
	std::unique_ptr<Impl> m_impl;
};
