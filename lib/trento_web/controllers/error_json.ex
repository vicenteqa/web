defmodule TrentoWeb.ErrorJSON do
  def render("400.json", %{reason: %{exception: exception}}) do
    %{
      errors: [
        %{
          title: "Bad Request",
          detail: Exception.message(exception)
        }
      ]
    }
  end

  def render("401.json", %{reason: reason}) do
    %{
      errors: [
        %{
          title: "Unauthorized",
          detail: reason
        }
      ]
    }
  end

  def render("403.json", %{reason: reason}) do
    %{
      errors: [
        %{
          title: "Forbidden",
          detail: reason
        }
      ]
    }
  end

  def render("403.json", %{errors: errors}) do
    %{
      errors:
        Enum.map(errors, fn error ->
          %{
            title: "Forbidden",
            detail: error
          }
        end)
    }
  end

  def render("403.json", _) do
    %{
      errors: [
        %{
          title: "Forbidden",
          detail: "You can't perform the operation or access the resource."
        }
      ]
    }
  end

  def render("404.json", %{reason: reason}) do
    %{
      errors: [
        %{
          title: "Not Found",
          detail: reason
        }
      ]
    }
  end

  def render("404.json", _) do
    %{
      errors: [
        %{
          title: "Not Found",
          detail: "The requested resource cannot be found."
        }
      ]
    }
  end

  def render("409.json", %{reason: reason}) do
    %{
      errors: [
        %{
          title: "Conflict has occurred",
          detail: reason
        }
      ]
    }
  end

  def render("422.json", %{changeset: changeset}) do
    error =
      Ecto.Changeset.traverse_errors(
        changeset,
        fn {message, opts} ->
          Regex.replace(~r"%{(\w+)}", message, fn _, key ->
            opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
          end)
        end
      )

    %{
      errors: render_validation_error(error, "")
    }
  end

  def render("422.json", %{reason: {:validation, error}}) do
    %{
      errors: render_validation_error(error, "")
    }
  end

  def render("422.json", %{reason: reason}) do
    %{
      errors: [
        %{
          title: "Unprocessable Entity",
          detail: reason
        }
      ]
    }
  end

  def render("500.json", _) do
    %{
      errors: [
        %{
          title: "Internal Server Error",
          detail: "Something went wrong."
        }
      ]
    }
  end

  def render("501.json", %{reason: reason}) do
    %{
      errors: [
        %{
          title: "Not implemented",
          detail: reason
        }
      ]
    }
  end

  def render("412.json", _) do
    %{
      errors: [
        %{
          title: "Precondition failed",
          detail:
            "Mid-air collision detected, please refresh the resource you are trying to update."
        }
      ]
    }
  end

  def render("428.json", _) do
    %{
      errors: [
        %{
          title: "Precondition required",
          detail: "Request needs to be conditional, please provide If-Match header."
        }
      ]
    }
  end

  def render(template, _assigns) do
    %{
      errors: [
        %{
          title: Phoenix.Controller.status_message_from_template(template),
          detail: "An error has occurred."
        }
      ]
    }
  end

  defp render_validation_error({key, value}, pointer) when is_map(value) do
    render_validation_error(value, "#{pointer}/#{key}")
  end

  defp render_validation_error({key, value}, pointer) when is_list(value) do
    Enum.map(value, &render_validation_error({key, &1}, pointer))
  end

  defp render_validation_error({key, value}, pointer) do
    %{
      title: "Invalid value",
      detail: value,
      source: %{
        pointer: "#{pointer}/#{key}"
      }
    }
  end

  defp render_validation_error(error, pointer) do
    Enum.flat_map(error, &render_validation_error(&1, pointer))
  end
end
