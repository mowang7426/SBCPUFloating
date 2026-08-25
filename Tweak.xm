import React, { useState, useEffect, useRef } from 'react';
import { 
  Cpu, Battery, Thermometer, Zap, Check, ChevronLeft, 
  Settings, Sliders, Smartphone, Code2, Eye, RefreshCw, 
  Sparkles, AlertTriangle, Layers, Move, CheckCircle2,
  SlidersHorizontal, CheckCircle, Info, ShieldCheck
} from 'lucide-react';

export default function App() {
  // Navigation & Fix Toggle States
  const [activeTab, setActiveTab] = useState('simulator'); // 'simulator' | 'code' | 'explanation'
  const [isFixed, setIsFixed] = useState(true); // Toggle Before vs After Fix
  const [currentScreen, setCurrentScreen] = useState('home'); // 'home' | 'settings_main' | 'settings_duration' | 'settings_cpu'
  const [selectedCodeTab, setSelectedCodeTab] = useState('tweak'); // 'tweak' | 'settings'

  // SBCPUFloating Preference States
  const [duration, setDuration] = useState(300); // default 300 seconds
  const [cpuThreshold, setCpuThreshold] = useState(100); // default 100%
  const [isEnabled, setIsEnabled] = useState(true);

  // Live Simulated Hardware Data
  const [cpuUsage, setCpuUsage] = useState(26.3);
  const [batteryLevel, setBatteryLevel] = useState(14);
  const [temp, setTemp] = useState(37.8);
  const [currentDraw, setCurrentDraw] = useState(-549);

  // Floating Window Position State (Draggable)
  const [pillPos, setPillPos] = useState({ x: 20, y: 180 });
  const [isDragging, setIsDragging] = useState(false);
  const dragStart = useRef({ x: 0, y: 0 });
  const pillStart = useRef({ x: 0, y: 0 });

  // Simulate subtle real-time fluctuation of CPU & current
  useEffect(() => {
    const interval = setInterval(() => {
      setCpuUsage(prev => +(Math.max(5, Math.min(190, prev + (Math.random() * 4 - 2)))).toFixed(1));
      setCurrentDraw(prev => Math.round(Math.max(-1200, Math.min(-150, prev + (Math.random() * 30 - 15)))));
    }, 2000);
    return () => clearInterval(interval);
  }, []);

  // Drag handlers for the floating window
  const handleMouseDown = (e) => {
    e.preventDefault();
    setIsDragging(true);
    const clientX = e.clientX || (e.touches && e.touches[0].clientX);
    const clientY = e.clientY || (e.touches && e.touches[0].clientY);
    dragStart.current = { x: clientX, y: clientY };
    pillStart.current = { ...pillPos };
  };

  const handleMouseMove = (e) => {
    if (!isDragging) return;
    const clientX = e.clientX || (e.touches && e.touches[0].clientX);
    const clientY = e.clientY || (e.touches && e.touches[0].clientY);
    const dx = clientX - dragStart.current.x;
    const dy = clientY - dragStart.current.y;
    
    // Bounds check within iPhone screen simulator (340x680)
    const newX = Math.max(10, Math.min(180, pillStart.current.x + dx));
    const newY = Math.max(60, Math.min(560, pillStart.current.y + dy));
    setPillPos({ x: newX, y: newY });
  };

  const handleMouseUp = () => {
    setIsDragging(false);
  };

  const durationOptions = [
    { label: '10 秒', value: 10 },
    { label: '30 秒', value: 30 },
    { label: '60 秒', value: 60 },
    { label: '120 秒', value: 120 },
    { label: '180 秒', value: 180 },
    { label: '300 秒', value: 300 },
    { label: '600 秒', value: 600 }
  ];

  const cpuOptions = [
    { label: '80%', value: 80 },
    { label: '100%', value: 100 },
    { label: '120%', value: 120 },
    { label: '140%', value: 140 },
    { label: '160%', value: 160 },
    { label: '180%', value: 180 },
    { label: '200%', value: 200 }
  ];

  return (
    <div className="flex flex-col min-h-screen bg-slate-950 text-slate-100 font-sans selection:bg-blue-500/30">
      {/* Top Header */}
      <header className="sticky top-0 z-50 backdrop-blur-md bg-slate-900/80 border-b border-slate-800 px-4 py-3">
        <div className="max-w-6xl mx-auto flex flex-col sm:flex-row items-center justify-between gap-3">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-gradient-to-tr from-blue-600 to-cyan-500 rounded-xl shadow-lg shadow-blue-500/20">
              <Cpu className="w-5 h-5 text-white" />
            </div>
            <div>
              <h1 className="font-bold text-lg leading-tight flex items-center gap-2">
                SBCPUFloating 阴影与点击修复
                <span className="text-xs font-normal px-2 py-0.5 rounded-full bg-blue-500/10 text-blue-400 border border-blue-500/20">
                  v2.0 精致版
                </span>
              </h1>
              <p className="text-xs text-slate-400">阴影重影修复 · 浮窗小巧精致化 · 设置页点击同步</p>
            </div>
          </div>

          {/* Navigation Tabs */}
          <div className="flex items-center bg-slate-800/80 p-1 rounded-lg border border-slate-700/50 text-xs font-medium">
            <button
              onClick={() => setActiveTab('simulator')}
              className={`flex items-center gap-1.5 px-3 py-1.5 rounded-md transition-all ${
                activeTab === 'simulator' 
                  ? 'bg-blue-600 text-white shadow-sm' 
                  : 'text-slate-400 hover:text-slate-200'
              }`}
            >
              <Smartphone className="w-3.5 h-3.5" />
              交互模拟器
            </button>
            <button
              onClick={() => setActiveTab('code')}
              className={`flex items-center gap-1.5 px-3 py-1.5 rounded-md transition-all ${
                activeTab === 'code' 
                  ? 'bg-blue-600 text-white shadow-sm' 
                  : 'text-slate-400 hover:text-slate-200'
              }`}
            >
              <Code2 className="w-3.5 h-3.5" />
              源代码修复 (Obj-C)
            </button>
            <button
              onClick={() => setActiveTab('explanation')}
              className={`flex items-center gap-1.5 px-3 py-1.5 rounded-md transition-all ${
                activeTab === 'explanation' 
                  ? 'bg-blue-600 text-white shadow-sm' 
                  : 'text-slate-400 hover:text-slate-200'
              }`}
            >
              <Info className="w-3.5 h-3.5" />
              问题分析与细节
            </button>
          </div>
        </div>
      </header>

      {/* Main Content Area */}
      <main className="flex-1 max-w-6xl w-full mx-auto p-4 md:p-6">
        {activeTab === 'simulator' && (
          <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 items-start">
            
            {/* Left Controls & Comparison Toggle */}
            <div className="lg:col-span-5 space-y-4">
              
              {/* Fix Status Switch Card */}
              <div className="bg-slate-900 border border-slate-800 rounded-2xl p-5 shadow-xl">
                <div className="flex items-center justify-between mb-4">
                  <h2 className="text-base font-semibold flex items-center gap-2">
                    <Sparkles className="w-4 h-4 text-cyan-400" />
                    效果模式对比
                  </h2>
                  <span className={`text-xs px-2.5 py-1 rounded-full font-medium ${
                    isFixed 
                      ? 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/20' 
                      : 'bg-amber-500/10 text-amber-400 border border-amber-500/20'
                  }`}>
                    {isFixed ? '已开启修复方案' : '原问题展示状态'}
                  </span>
                </div>

                <div className="grid grid-cols-2 gap-2 bg-slate-950 p-1 rounded-xl border border-slate-800">
                  <button
                    onClick={() => setIsFixed(false)}
                    className={`py-2 px-3 rounded-lg text-xs font-medium transition-all flex flex-col items-center gap-1 ${
                      !isFixed 
                        ? 'bg-slate-800 text-amber-300 border border-amber-500/30 shadow-md' 
                        : 'text-slate-400 hover:text-slate-200'
                    }`}
                  >
                    <AlertTriangle className="w-4 h-4 text-amber-400" />
                    <span>修复前 (有重影阴影)</span>
                  </button>

                  <button
                    onClick={() => setIsFixed(true)}
                    className={`py-2 px-3 rounded-lg text-xs font-medium transition-all flex flex-col items-center gap-1 ${
                      isFixed 
                        ? 'bg-blue-600 text-white shadow-md shadow-blue-500/20' 
                        : 'text-slate-400 hover:text-slate-200'
                    }`}
                  >
                    <CheckCircle className="w-4 h-4 text-emerald-300" />
                    <span>修复后 (精致无重影)</span>
                  </button>
                </div>

                {/* Status Bullet Points */}
                <div className="mt-4 pt-4 border-t border-slate-800/80 space-y-2 text-xs">
                  <div className="flex items-start gap-2 text-slate-300">
                    <span className={`w-1.5 h-1.5 rounded-full mt-1.5 flex-shrink-0 ${isFixed ? 'bg-emerald-400' : 'bg-amber-400'}`} />
                    <span>
                      {isFixed 
                        ? '阴影重影：已去除底部黑色多余虚影，阴影模糊精准贴合边缘。' 
                        : '阴影重影：底部保留有深色双重阴影（如图中箭头标出的位置）。'}
                    </span>
                  </div>
                  <div className="flex items-start gap-2 text-slate-300">
                    <span className={`w-1.5 h-1.5 rounded-full mt-1.5 flex-shrink-0 ${isFixed ? 'bg-emerald-400' : 'bg-amber-400'}`} />
                    <span>
                      {isFixed 
                        ? '尺寸外观：已缩减整体尺寸（边距/字号精致化），极简好看。' 
                        : '尺寸外观：原始较宽大圆角胶囊形态。'}
                    </span>
                  </div>
                  <div className="flex items-start gap-2 text-slate-300">
                    <span className={`w-1.5 h-1.5 rounded-full mt-1.5 flex-shrink-0 ${isFixed ? 'bg-emerald-400' : 'bg-amber-400'}`} />
                    <span>
                      {isFixed 
                        ? '设置点击：点击"持续时间"或"CPU触发值"项，打勾(✓)实时切换并即刻刷新！' 
                        : '设置点击：点击选项无反应或不会更新勾选。'}
                    </span>
                  </div>
                </div>
              </div>

              {/* Hardware Data Slider Controls */}
              <div className="bg-slate-900 border border-slate-800 rounded-2xl p-5 shadow-xl space-y-4">
                <h3 className="text-sm font-semibold flex items-center gap-2 text-slate-200">
                  <SlidersHorizontal className="w-4 h-4 text-blue-400" />
                  模拟数据调参 (实时更新浮窗)
                </h3>

                <div className="space-y-3 text-xs">
                  <div>
                    <div className="flex justify-between text-slate-400 mb-1">
                      <span>CPU 使用率 (SB CPU)</span>
                      <span className="font-mono font-bold text-blue-400">{cpuUsage}%</span>
                    </div>
                    <input 
                      type="range" 
                      min="5" 
                      max="200" 
                      step="0.1" 
                      value={cpuUsage} 
                      onChange={(e) => setCpuUsage(parseFloat(e.target.value))}
                      className="w-full h-1.5 bg-slate-800 rounded-lg appearance-none cursor-pointer accent-blue-500"
                    />
                  </div>

                  <div>
                    <div className="flex justify-between text-slate-400 mb-1">
                      <span>电池电量 (Battery)</span>
                      <span className="font-mono font-bold text-emerald-400">{batteryLevel}%</span>
                    </div>
                    <input 
                      type="range" 
                      min="1" 
                      max="100" 
                      value={batteryLevel} 
                      onChange={(e) => setBatteryLevel(parseInt(e.target.value))}
                      className="w-full h-1.5 bg-slate-800 rounded-lg appearance-none cursor-pointer accent-emerald-500"
                    />
                  </div>

                  <div>
                    <div className="flex justify-between text-slate-400 mb-1">
                      <span>电池温度 (Temp)</span>
                      <span className="font-mono font-bold text-amber-400">{temp}°C</span>
                    </div>
                    <input 
                      type="range" 
                      min="20" 
                      max="50" 
                      step="0.1" 
                      value={temp} 
                      onChange={(e) => setTemp(parseFloat(e.target.value))}
                      className="w-full h-1.5 bg-slate-800 rounded-lg appearance-none cursor-pointer accent-amber-500"
                    />
                  </div>

                  <div>
                    <div className="flex justify-between text-slate-400 mb-1">
                      <span>充放电电流 (Current)</span>
                      <span className="font-mono font-bold text-cyan-400">{currentDraw}mA</span>
                    </div>
                    <input 
                      type="range" 
                      min="-1500" 
                      max="1000" 
                      step="10" 
                      value={currentDraw} 
                      onChange={(e) => setCurrentDraw(parseInt(e.target.value))}
                      className="w-full h-1.5 bg-slate-800 rounded-lg appearance-none cursor-pointer accent-cyan-500"
                    />
                  </div>
                </div>
              </div>

              {/* Quick Jump Buttons for iPhone Screens */}
              <div className="bg-slate-900 border border-slate-800 rounded-2xl p-4 shadow-xl flex items-center justify-between text-xs">
                <span className="text-slate-400">切换手机界面:</span>
                <div className="flex gap-2">
                  <button 
                    onClick={() => setCurrentScreen('home')}
                    className={`px-3 py-1.5 rounded-lg border transition-all ${
                      currentScreen === 'home' 
                        ? 'bg-blue-600/20 text-blue-300 border-blue-500/40' 
                        : 'bg-slate-800/60 border-slate-700/50 text-slate-400'
                    }`}
                  >
                    桌面 (看浮窗)
                  </button>
                  <button 
                    onClick={() => setCurrentScreen('settings_main')}
                    className={`px-3 py-1.5 rounded-lg border transition-all ${
                      currentScreen.startsWith('settings') 
                        ? 'bg-blue-600/20 text-blue-300 border-blue-500/40' 
                        : 'bg-slate-800/60 border-slate-700/50 text-slate-400'
                    }`}
                  >
                    设置页 (测试点击)
                  </button>
                </div>
              </div>

            </div>

            {/* Right Interactive Phone Simulator Frame */}
            <div className="lg:col-span-7 flex flex-col items-center">
              
              {/* iPhone Frame */}
              <div 
                className="relative w-[340px] h-[680px] bg-slate-900 rounded-[48px] p-3 shadow-2xl border-[4px] border-slate-700/80 ring-1 ring-slate-950/80 overflow-hidden select-none"
                onMouseMove={handleMouseMove}
                onMouseUp={handleMouseUp}
                onTouchMove={handleMouseMove}
                onTouchEnd={handleMouseUp}
              >
                {/* Dynamic Island / Notch */}
                <div className="absolute top-5 left-1/2 -translate-x-1/2 w-28 h-7 bg-black rounded-full z-40 flex items-center justify-between px-2.5 shadow-md">
                  <div className="w-2.5 h-2.5 rounded-full bg-blue-900/60 border border-blue-500/40 flex items-center justify-center">
                    <div className="w-1 h-1 rounded-full bg-blue-400"></div>
                  </div>
                  <div className="text-[10px] text-slate-400 font-mono scale-90">1380 消息</div>
                </div>

                {/* Inner Screen Wallpaper Container */}
                <div className="relative w-full h-full rounded-[38px] overflow-hidden bg-slate-900 flex flex-col">
                  
                  {/* Screen Content Switcher */}
                  {currentScreen === 'home' && (
                    <div className="relative w-full h-full bg-gradient-to-b from-neutral-800 via-stone-900 to-black p-4 pt-16 flex flex-col justify-between">
                      
                      {/* Wallpaper App Icons */}
                      <div className="grid grid-cols-4 gap-4 pt-4">
                        <div className="flex flex-col items-center gap-1">
                          <div className="w-12 h-12 bg-gradient-to-tr from-orange-500 to-red-500 rounded-2xl shadow-lg flex items-center justify-center text-white text-xl font-bold">
                            💥
                          </div>
                          <span className="text-[10px] text-white/90">火花</span>
                        </div>

                        <div className="flex flex-col items-center gap-1">
                          <div className="w-12 h-12 bg-slate-950 border border-cyan-500/40 rounded-2xl shadow-lg flex items-center justify-center text-cyan-400 text-lg font-bold">
                            AI
                          </div>
                          <span className="text-[10px] text-white/90 font-mono">Fuck</span>
                        </div>

                        <div 
                          onClick={() => setCurrentScreen('settings_main')}
                          className="flex flex-col items-center gap-1 cursor-pointer group"
                        >
                          <div className="w-12 h-12 bg-slate-800 rounded-2xl shadow-lg border border-slate-700 flex items-center justify-center group-hover:scale-105 transition-transform">
                            <Settings className="w-6 h-6 text-slate-300" />
                          </div>
                          <span className="text-[10px] text-white/90">SBCPU设置</span>
                        </div>
                      </div>

                      <div className="text-center text-[11px] text-slate-500 mb-12">
                        拖拽浮窗可自定义位置
                      </div>

                      {/* Home Screen Touch Assistive Button */}
                      <div className="absolute bottom-6 right-6 w-11 h-11 rounded-full bg-white/20 backdrop-blur-md border border-white/30 flex items-center justify-center shadow-lg">
                        <div className="w-8 h-8 rounded-full bg-white/40 border border-white/50" />
                      </div>
                    </div>
                  )}

                  {/* Settings Main Screen */}
                  {currentScreen === 'settings_main' && (
                    <div className="w-full h-full bg-slate-100 text-slate-900 pt-16 px-4 flex flex-col">
                      <div className="flex items-center gap-2 mb-6">
                        <ChevronLeft 
                          onClick={() => setCurrentScreen('home')}
                          className="w-6 h-6 text-blue-600 cursor-pointer" 
                        />
                        <h2 className="text-lg font-bold text-blue-600 tracking-tight">SBCPUFloating 设置</h2>
                      </div>

                      <div className="bg-white rounded-2xl shadow-sm border border-slate-200/80 overflow-hidden space-y-0 text-sm">
                        <div 
                          onClick={() => setCurrentScreen('settings_duration')}
                          className="p-4 flex items-center justify-between border-b border-slate-100 cursor-pointer hover:bg-slate-50 transition-colors"
                        >
                          <span className="font-medium text-slate-800">持续时间</span>
                          <div className="flex items-center gap-2 text-slate-400 text-xs">
                            <span>{duration} 秒</span>
                            <ChevronLeft className="w-4 h-4 rotate-180" />
                          </div>
                        </div>

                        <div 
                          onClick={() => setCurrentScreen('settings_cpu')}
                          className="p-4 flex items-center justify-between cursor-pointer hover:bg-slate-50 transition-colors"
                        >
                          <span className="font-medium text-slate-800">CPU 触发值</span>
                          <div className="flex items-center gap-2 text-slate-400 text-xs">
                            <span>{cpuThreshold}%</span>
                            <ChevronLeft className="w-4 h-4 rotate-180" />
                          </div>
                        </div>
                      </div>

                      <p className="text-[11px] text-slate-400 mt-3 px-2">
                        修改参数后无需重启 SpringBoard，生效提示框将在顶部通知中心显示。
                      </p>
                    </div>
                  )}

                  {/* Settings Duration Detail Page */}
                  {currentScreen === 'settings_duration' && (
                    <div className="w-full h-full bg-slate-100 text-slate-900 pt-16 px-4 flex flex-col">
                      <div className="flex items-center gap-2 mb-4">
                        <ChevronLeft 
                          onClick={() => setCurrentScreen('settings_main')}
                          className="w-6 h-6 text-blue-600 cursor-pointer" 
                        />
                        <h2 className="text-lg font-bold text-blue-600 tracking-tight">SBCPUFloating 设置</h2>
                      </div>

                      <div className="text-xs text-slate-500 font-semibold mb-2 px-1">持续时间</div>

                      <div className="bg-white rounded-2xl shadow-sm border border-slate-200/80 overflow-hidden text-sm">
                        {durationOptions.map((opt, idx) => (
                          <div 
                            key={opt.value}
                            onClick={() => {
                              setDuration(opt.value);
                            }}
                            className={`p-3.5 flex items-center justify-between cursor-pointer transition-colors ${
                              idx !== durationOptions.length - 1 ? 'border-b border-slate-100' : ''
                            } ${duration === opt.value ? 'bg-slate-100/60' : 'hover:bg-slate-50'}`}
                          >
                            <span className="font-bold text-slate-800 font-mono">{opt.label}</span>
                            {duration === opt.value && (
                              <Check className="w-5 h-5 text-blue-600 font-bold" />
                            )}
                          </div>
                        ))}
                      </div>
                    </div>
                  )}

                  {/* Settings CPU Trigger Detail Page */}
                  {currentScreen === 'settings_cpu' && (
                    <div className="w-full h-full bg-slate-100 text-slate-900 pt-16 px-4 flex flex-col">
                      <div className="flex items-center gap-2 mb-4">
                        <ChevronLeft 
                          onClick={() => setCurrentScreen('settings_main')}
                          className="w-6 h-6 text-blue-600 cursor-pointer" 
                        />
                        <h2 className="text-lg font-bold text-blue-600 tracking-tight">SBCPUFloating 设置</h2>
                      </div>

                      <div className="text-xs text-slate-500 font-semibold mb-2 px-1">CPU 触发值</div>

                      <div className="bg-white rounded-2xl shadow-sm border border-slate-200/80 overflow-hidden text-sm">
                        {cpuOptions.map((opt, idx) => (
                          <div 
                            key={opt.value}
                            onClick={() => {
                              setCpuThreshold(opt.value);
                            }}
                            className={`p-3.5 flex items-center justify-between cursor-pointer transition-colors ${
                              idx !== cpuOptions.length - 1 ? 'border-b border-slate-100' : ''
                            } ${cpuThreshold === opt.value ? 'bg-slate-100/60' : 'hover:bg-slate-50'}`}
                          >
                            <span className="font-bold text-slate-800 font-mono">{opt.label}</span>
                            {cpuThreshold === opt.value && (
                              <Check className="w-5 h-5 text-blue-600 font-bold" />
                            )}
                          </div>
                        ))}
                      </div>
                    </div>
                  )}

                  {/* FLOATING OVERLAY WIDGET (Simulating Tweak View) */}
                  {isEnabled && (
                    <div
                      onMouseDown={handleMouseDown}
                      onTouchStart={handleMouseDown}
                      style={{
                        top: `${pillPos.y}px`,
                        left: `${pillPos.x}px`
                      }}
                      className="absolute z-50 cursor-move transition-transform active:scale-95 touch-none"
                    >
                      {/* BEFORE FIX (Original Buggy Render) */}
                      {!isFixed && (
                        <div className="relative">
                          {/* THE BUGGY DUPLICATE SHADOW BELOW (Pointed out by user's red arrows) */}
                          <div className="absolute top-6 left-0 right-0 h-14 bg-black/50 blur-md rounded-3xl opacity-80 pointer-events-none transform translate-y-3" />
                          <div className="absolute top-10 left-2 right-2 h-10 bg-slate-900/60 blur-lg rounded-full pointer-events-none" />

                          {/* Large Old Pill */}
                          <div className="relative bg-gradient-to-b from-stone-700/80 via-stone-800/90 to-black/90 backdrop-blur-md rounded-[32px] p-4 border border-white/30 text-white shadow-2xl min-w-[210px]">
                            <div className="text-sm font-bold tracking-tight text-white/95 mb-1 text-center font-mono">
                              SB CPU {cpuUsage}%
                            </div>
                            <div className="flex items-center justify-center gap-2 text-xs font-semibold font-mono">
                              <span className="flex items-center gap-0.5 text-emerald-400">
                                🔋 {batteryLevel}%
                              </span>
                              <span className="flex items-center gap-0.5 text-red-400">
                                🌡️ {temp}°C
                              </span>
                            </div>
                            <div className="text-center text-xs font-mono text-slate-300 mt-0.5">
                              {currentDraw}mA
                            </div>
                          </div>
                        </div>
                      )}

                      {/* AFTER FIX (Fixed Modern Sleek Refined Mini Pill) */}
                      {isFixed && (
                        <div className="relative group">
                          {/* Clean subtle drop shadow with exact path match */}
                          <div className="absolute inset-0 bg-black/30 rounded-2xl blur-sm transform translate-y-1" />
                          
                          {/* Mini Compact Glassmorphism Container */}
                          <div className="relative bg-slate-900/75 backdrop-blur-xl rounded-2xl px-3.5 py-2 border border-white/20 text-white shadow-xl flex flex-col items-center gap-0.5 min-w-[155px]">
                            <div className="flex items-center justify-between w-full text-[11px] font-bold font-mono text-slate-100 border-b border-white/10 pb-1">
                              <span className="text-slate-300 text-[10px]">SB CPU</span>
                              <span className={`px-1 rounded ${cpuUsage > cpuThreshold ? 'bg-red-500/80 text-white animate-pulse' : 'text-blue-300'}`}>
                                {cpuUsage}%
                              </span>
                            </div>

                            <div className="flex items-center justify-between w-full gap-2 text-[10px] font-mono text-slate-200 pt-0.5">
                              <div className="flex items-center gap-0.5 text-emerald-400">
                                <Battery className="w-3 h-3" />
                                <span>{batteryLevel}%</span>
                              </div>
                              <div className="flex items-center gap-0.5 text-amber-300">
                                <Thermometer className="w-3 h-3" />
                                <span>{temp}°</span>
                              </div>
                              <div className="flex items-center gap-0.5 text-cyan-300 font-medium">
                                <Zap className="w-3 h-3" />
                                <span>{currentDraw}mA</span>
                              </div>
                            </div>
                          </div>
                        </div>
                      )}

                    </div>
                  )}

                </div>
              </div>
              <p className="text-xs text-slate-500 mt-2">提示：浮窗可按住拖拽。点击"设置页"可测试打勾逻辑。</p>
            </div>

          </div>
        )}

        {/* Code View Tab */}
        {activeTab === 'code' && (
          <div className="space-y-4">
            {/* Code sub-tabs */}
            <div className="flex gap-2 border-b border-slate-800 pb-2">
              <button
                onClick={() => setSelectedCodeTab('tweak')}
                className={`px-4 py-2 rounded-lg text-xs font-mono transition-all ${
                  selectedCodeTab === 'tweak'
                    ? 'bg-blue-600 text-white font-bold'
                    : 'bg-slate-900 text-slate-400 hover:text-slate-200'
                }`}
              >
                Tweak.x (阴影与精致浮窗 UI 修复)
              </button>
              <button
                onClick={() => setSelectedCodeTab('settings')}
                className={`px-4 py-2 rounded-lg text-xs font-mono transition-all ${
                  selectedCodeTab === 'settings'
                    ? 'bg-blue-600 text-white font-bold'
                    : 'bg-slate-900 text-slate-400 hover:text-slate-200'
                }`}
              >
                SBCPUFloatingListController.m (点击打勾与存储修复)
              </button>
            </div>

            {/* Code Display */}
            {selectedCodeTab === 'tweak' && (
              <div className="bg-slate-900 border border-slate-800 rounded-2xl p-4 font-mono text-xs overflow-x-auto text-slate-200 shadow-2xl">
                <div className="text-slate-400 mb-3 border-b border-slate-800 pb-2 flex justify-between items-center">
                  <span>// Tweak.x - 解决阴影虚影 + 极简精致 Mini 浮窗</span>
                  <span className="text-emerald-400 text-[10px]">Objective-C / Logos</span>
                </div>
                <pre className="leading-relaxed">
{`#import <UIKit/UIKit.h>

@interface SBCPUFloatingView : UIView
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) UILabel *cpuLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@end

@implementation SBCPUFloatingView

- (instancetype)initWithFrame:(CGRect)frame {
    // 关键改变：缩减默认宽高，从原来的宽大胶囊缩小至精致尺寸 (155 x 38)
    CGRect compactFrame = CGRectMake(frame.origin.x, frame.origin.y, 155.0f, 38.0f);
    if (self = [super initWithFrame:compactFrame]) {
        
        // ----------------------------------------------------
        // 修复 1：解决底部重影阴影 (Shadow Artefact Fix)
        // ----------------------------------------------------
        // 必须设置背景透明，防止 View 本身背景色在毛玻璃后被重复渲染成深色阴影
        self.backgroundColor = [UIColor clearColor];
        
        // 单层细腻阴影配置
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.25f;
        self.layer.shadowOffset = CGSizeMake(0, 3);
        self.layer.shadowRadius = 6.0f;
        self.layer.masksToBounds = NO; // 外层不能 Mask，否则阴影出不来
        
        // ----------------------------------------------------
        // 修复 2：毛玻璃背景层 (Backdrop Blur & Compact Layout)
        // ----------------------------------------------------
        UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
        _blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
        _blurView.frame = self.bounds;
        _blurView.layer.cornerRadius = 14.0f; // 精致圆角
        _blurView.layer.masksToBounds = YES;  // 关键：毛玻璃层内裁切，禁止底图滤镜溢出生成额外虚影
        
        // 加入 0.5px 极细质感边框
        _blurView.layer.borderWidth = 0.5f;
        _blurView.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:0.2f].CGColor;
        [self addSubview:_blurView];
        
        // 关键绑定：阴影路径与圆角严格匹配，提升性能且避免重影
        self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:14.0f].CGPath;
        
        // 构建精致布局组件...
        [self setupSubviews];
    }
    return self;
}

- (void)setupSubviews {
    // CPU 文本行
    _cpuLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 4, 135, 14)];
    _cpuLabel.font = [UIFont fontWithName:@"HelveticaNeue-Bold" size:11.0f];
    _cpuLabel.textColor = [UIColor whiteColor];
    
    // 细节数据行 (电量 / 温度 / 电流)
    _detailLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 19, 135, 14)];
    _detailLabel.font = [UIFont fontWithName:@"HelveticaNeue-Medium" size:10.0f];
    _detailLabel.textColor = [UIColor colorWithWhite:0.9f alpha:1.0f];
    
    [_blurView.contentView addSubview:_cpuLabel];
    [_blurView.contentView addSubview:_detailLabel];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _blurView.frame = self.bounds;
    // 重新更新精确的 Shadow Path，防止动画或拖拽时阴影错位
    self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:14.0f].CGPath;
}

@end`}
                </pre>
              </div>
            )}

            {selectedCodeTab === 'settings' && (
              <div className="bg-slate-900 border border-slate-800 rounded-2xl p-4 font-mono text-xs overflow-x-auto text-slate-200 shadow-2xl">
                <div className="text-slate-400 mb-3 border-b border-slate-800 pb-2 flex justify-between items-center">
                  <span>// SBCPUFloatingListController.m - 解决点击打勾无反应与保存</span>
                  <span className="text-emerald-400 text-[10px]">PreferenceBundle</span>
                </div>
                <pre className="leading-relaxed">
{`#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

@interface SBCPUFloatingDetailController : PSListController
@property (nonatomic, strong) NSArray *optionsList;
@property (nonatomic, assign) NSInteger selectedIndex;
@property (nonatomic, NSString *) preferenceKey; // @"duration" 或 @"cpuThreshold"
@end

@implementation SBCPUFloatingDetailController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // 读取当前已保存的值，计算 index
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.yourname.sbcpufloating.plist"];
    id currentValue = prefs[self.preferenceKey];
    
    // 初始化 selectedIndex...
}

// ----------------------------------------------------
// 修复 3：重写 didSelectRowAtIndexPath 点击代理方法
// ----------------------------------------------------
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    // 1. 更新选中的索引
    self.selectedIndex = indexPath.row;
    id selectedValue = self.optionsList[indexPath.row];
    
    // 2. 写入 plist 配置文件
    NSString *plistPath = @"/var/mobile/Library/Preferences/com.yourname.sbcpufloating.plist";
    NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:plistPath] ?: [NSMutableDictionary dictionary];
    [prefs setObject:selectedValue forKey:self.preferenceKey];
    [prefs writeToFile:plistPath atomically:YES];
    
    // 3. 发送 Darwin 广播通知 SpringBoard 中的 Tweak 即时刷新
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.yourname.sbcpufloating.prefschanged"),
        NULL, NULL, YES
    );
    
    // 4. 关键：重新加载 TableView 视图，刷新打勾 (Checkmark) 状态！
    [tableView reloadData];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"OptionCell"];
    }
    
    // 根据当前 selectedIndex 动态控制 Checkmark 显示
    if (indexPath.row == self.selectedIndex) {
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
    } else {
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    
    return cell;
}`}
                </pre>
              </div>
            )}
          </div>
        )}

        {/* Explanation Tab */}
        {activeTab === 'explanation' && (
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div className="bg-slate-900 border border-slate-800 rounded-2xl p-5 space-y-3">
              <div className="w-9 h-9 rounded-xl bg-amber-500/10 border border-amber-500/20 flex items-center justify-center text-amber-400">
                <Layers className="w-5 h-5" />
              </div>
              <h3 className="font-bold text-slate-100 text-sm">1. 底部阴影重影问题</h3>
              <p className="text-xs text-slate-400 leading-relaxed">
                原 UI 视图中，外层 `UIView` 和内部的 `UIVisualEffectView`（毛玻璃层）都施加了阴影/背景色，导致底部渲染出了一块半透明黑影。通过去除多余 View 的背景色并绑定 `shadowPath`，彻底解除了底层虚影。
              </p>
            </div>

            <div className="bg-slate-900 border border-slate-800 rounded-2xl p-5 space-y-3">
              <div className="w-9 h-9 rounded-xl bg-blue-500/10 border border-blue-500/20 flex items-center justify-center text-blue-400">
                <Sparkles className="w-5 h-5" />
              </div>
              <h3 className="font-bold text-slate-100 text-sm">2. 浮窗形态小巧精致化</h3>
              <p className="text-xs text-slate-400 leading-relaxed">
                原浮窗较为宽大占地方。优化后将宽度缩减至 155px，高缩减至 38px，边距精简至 8px/14px，加入了 0.5px 薄白光边框与动态 CPU 超高高亮警示，显得极为小巧与精致。
              </p>
            </div>

            <div className="bg-slate-900 border border-slate-800 rounded-2xl p-5 space-y-3">
              <div className="w-9 h-9 rounded-xl bg-emerald-500/10 border border-emerald-500/20 flex items-center justify-center text-emerald-400">
                <CheckCircle2 className="w-5 h-5" />
              </div>
              <h3 className="font-bold text-slate-100 text-sm">3. 设置页点击打勾修复</h3>
              <p className="text-xs text-slate-400 leading-relaxed">
                `didSelectRowAtIndexPath` 代理未触发刷新或未保存 key 值。重写了设置控制器后，现在点击任何秒数或百分比即可瞬时切换打勾 (`✓`) 状态并写入配置通知。
              </p>
            </div>
          </div>
        )}
      </main>
    </div>
  );
}

