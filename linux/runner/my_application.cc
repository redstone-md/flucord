#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
  FlMethodChannel* protocol_channel;
  GQueue* pending_protocol_urls;
  gboolean protocol_ready;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

static void dispatch_protocol_url(MyApplication* self, const gchar* url) {
  if (!g_str_has_prefix(url, "flucord://")) {
    return;
  }
  if (!self->protocol_ready || self->protocol_channel == nullptr) {
    g_queue_push_tail(self->pending_protocol_urls, g_strdup(url));
    return;
  }
  g_autoptr(FlValue) value = fl_value_new_string(url);
  fl_method_channel_invoke_method(self->protocol_channel, "url", value,
                                  nullptr, nullptr, nullptr);
}

static void protocol_channel_method_call_cb(FlMethodChannel*,
                                            FlMethodCall* method_call,
                                            gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (g_strcmp0(fl_method_call_get_name(method_call), "ready") != 0) {
    fl_method_call_respond_not_implemented(method_call, nullptr);
    return;
  }

  self->protocol_ready = TRUE;
  while (!g_queue_is_empty(self->pending_protocol_urls)) {
    gchar* url = static_cast<gchar*>(
        g_queue_pop_head(self->pending_protocol_urls));
    dispatch_protocol_url(self, url);
    g_free(url);
  }
  fl_method_call_respond_success(method_call, nullptr, nullptr);
}

static void window_destroy_cb(GtkWidget* widget, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (self->window != GTK_WINDOW(widget)) {
    return;
  }
  self->window = nullptr;
  self->protocol_ready = FALSE;
  g_clear_object(&self->protocol_channel);
  g_queue_clear_full(self->pending_protocol_urls, g_free);
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  if (self->window != nullptr) {
    gtk_window_present(self->window);
    return;
  }
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  self->window = window;
  g_signal_connect(window, "destroy", G_CALLBACK(window_destroy_cb), self);

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Flucord");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Flucord");
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->protocol_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "flucord/protocol", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->protocol_channel, protocol_channel_method_call_cb, self, nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Runs in the primary process for both the initial and forwarded invocations.
static int my_application_command_line(GApplication* application,
                                       GApplicationCommandLine* command_line) {
  MyApplication* self = MY_APPLICATION(application);
  int argument_count = 0;
  g_auto(GStrv) arguments =
      g_application_command_line_get_arguments(command_line, &argument_count);
  if (self->window == nullptr) {
    g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
    self->dart_entrypoint_arguments = g_strdupv(arguments + 1);
  } else {
    for (int index = 1; index < argument_count; index++) {
      dispatch_protocol_url(self, arguments[index]);
    }
  }

  g_application_activate(application);
  return 0;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_object(&self->protocol_channel);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  if (self->pending_protocol_urls != nullptr) {
    g_queue_free_full(self->pending_protocol_urls, g_free);
    self->pending_protocol_urls = nullptr;
  }
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->command_line = my_application_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->pending_protocol_urls = g_queue_new();
}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_HANDLES_COMMAND_LINE,
                                     nullptr));
}
