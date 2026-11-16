#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <cwchar>

#include "flutter_window.h"
#include "utils.h"

// Comentarios deste arquivo sem acentos de proposito: o compilador do
// Windows le o fonte na pagina de codigo do sistema, e um caractere fora
// dela vira aviso, que este projeto trata como erro.

namespace {

// Titulo da janela.
const wchar_t kWindowTitle[] = L"ORION ServiceLog";

// Nome do bloqueio que marca "o ORION ja esta aberto" na sessao do usuario.
const wchar_t kInstanceMutex[] = L"br.com.orionmed.servicelog_ai";

// Classe de janela registrada em win32_window.cpp. Todo aplicativo Flutter
// usa a mesma, entao ela sozinha nao identifica o ORION.
const wchar_t kRunnerWindowClass[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

// Traz para a frente a janela do ORION que ja esta aberta.
//
// Compara so o comeco do titulo: o Flutter pode troca-lo pelo titulo do
// aplicativo ("ORION ServiceLog AI"), que comeca igual.
void ActivateRunningInstance() {
  const size_t prefix_length = ::wcslen(kWindowTitle);
  for (HWND candidate =
           ::FindWindowExW(nullptr, nullptr, kRunnerWindowClass, nullptr);
       candidate != nullptr;
       candidate = ::FindWindowExW(nullptr, candidate, kRunnerWindowClass,
                                   nullptr)) {
    wchar_t title[128] = {};
    ::GetWindowTextW(candidate, title, 128);
    if (::wcsncmp(title, kWindowTitle, prefix_length) != 0) {
      continue;
    }
    if (::IsIconic(candidate)) {
      ::ShowWindow(candidate, SW_RESTORE);
    }
    ::SetForegroundWindow(candidate);
    return;
  }
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Uma janela so. O aplicativo carrega a base local inteira na memoria e
  // grava de volta a cada alteracao: com duas janelas abertas, a que
  // gravasse por ultimo apagaria o que a outra acabou de salvar. No
  // Windows um clique duplo a mais no atalho ja abriria a segunda.
  HANDLE instance_mutex = ::CreateMutexW(nullptr, FALSE, kInstanceMutex);
  if (instance_mutex && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    ActivateRunningInstance();
    ::CloseHandle(instance_mutex);
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(kWindowTitle, origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
