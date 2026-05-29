#pragma once

#include <iosfwd>
#include <string>

#include <libworld/export.hxx>

namespace world
{
  // Print a greeting for the specified name into the specified
  // stream. Throw std::invalid_argument if the name is empty.
  //
  LIBWORLD_SYMEXPORT void
  say_hello (std::ostream&, const std::string& name);
}
