#===============================================================================
# MOD: 097_Asynchronous_Save
#-------------------------------------------------------------------------------
# Implementa salvamento assíncrono (multithreaded) no jogo.
# Serializa os dados no thread principal (rápido, ~5-15ms) e escreve o arquivo
# de save no disco em um thread de background para evitar travamentos/stutters.
# Inclui dupla-gravação (.tmp -> rename) contra corrupção de save e auto-espera
# ao fechar, deletar, existir ou carregar o arquivo.
#===============================================================================

module AnilAsyncSave
  @save_thread = nil
  @save_mutex = Mutex.new
  @failed_message = nil

  class << self
    attr_accessor :failed_message

    def active?
      return !@save_thread.nil? && @save_thread.alive?
    end

    def write_async(file_path, data_string)
      # Se já houver um salvamento em progresso, aguarda a finalização
      if active?
        AnilLanRework.log("[AsyncSave] Aguardando salvamento anterior concluir...") rescue nil
        wait_for_save
      end

      @failed_message = nil

      @save_thread = Thread.new do
        @save_mutex.synchronize do
          begin
            temp_path = file_path + ".tmp"
            bak_path = file_path + ".bak"

            # 1. Escreve no arquivo temporário
            File.open(temp_path, "wb") do |file|
              file.write(data_string)
            end

            # 2. Gera backup do save antigo se ele existir
            if File.exist?(file_path)
              begin
                File.delete(bak_path) if File.exist?(bak_path)
                File.rename(file_path, bak_path)
              rescue => backup_err
                AnilLanRework.log("[AsyncSave] Aviso ao criar backup: #{backup_err.message}") rescue nil
              end
            end

            # 3. Renomeia o temporário para o destino final (operação atômica)
            File.rename(temp_path, file_path)

            AnilLanRework.log("[AsyncSave] Jogo salvo com sucesso em: #{file_path}") rescue nil
          rescue => e
            @failed_message = "ERRO CRÍTICO AO SALVAR O JOGO: #{e.message}\nVerifique seu espaço em disco!"
            msg = "[AsyncSave] ERRO AO GRAVAR SAVE NO DISCO: #{e.message}\n#{e.backtrace.join("\n")}"
            if defined?(AnilLanRework)
              AnilLanRework.log(msg)
            else
              echoln msg rescue nil
            end
          end
        end
      end
    end

    def wait_for_save
      if @save_thread
        @save_thread.join rescue nil
        @save_thread = nil
      end
    end
  end
end

# Garante que o thread de gravação termine antes do processo do jogo ser fechado
at_exit do
  AnilAsyncSave.wait_for_save
end

#===============================================================================
# Monkey patches no SaveData para garantir consistência e multithreading
#===============================================================================
module SaveData
  class << self
    # Intercepta as checagens e leituras para garantir que o save no background terminou
    if !method_defined?(:anil_async_save_original_exists?)
      alias_method :anil_async_save_original_exists?, :exists?
      def exists?
        AnilAsyncSave.wait_for_save
        anil_async_save_original_exists?
      end
    end

    if !method_defined?(:anil_async_save_original_get_data_from_file)
      alias_method :anil_async_save_original_get_data_from_file, :get_data_from_file
      def get_data_from_file(file_path)
        AnilAsyncSave.wait_for_save
        anil_async_save_original_get_data_from_file(file_path.to_s)
      end
    end

    if !method_defined?(:anil_async_save_original_delete_file)
      alias_method :anil_async_save_original_delete_file, :delete_file
      def delete_file
        AnilAsyncSave.wait_for_save
        anil_async_save_original_delete_file
      end
    end

    # Sobrescreve o salvamento de fato para ser assíncrono
    if !method_defined?(:anil_async_save_original_save_to_file)
      alias_method :anil_async_save_original_save_to_file, :save_to_file
      def save_to_file(file_path)
        path_str = file_path.to_s
        save_data = self.compile_save_hash
        # Serializa para string no main thread (sincrono e ultra rápido)
        serialized_str = Marshal.dump(save_data)
        # Envia a gravação em disco para o thread de background
        AnilAsyncSave.write_async(path_str, serialized_str)
      end
    end
  end
end

#===============================================================================
# Hook na atualização do mapa para exibir erros de salvamento em background
#===============================================================================
class Scene_Map
  if !method_defined?(:anil_async_save_original_update)
    alias_method :anil_async_save_original_update, :update
    def update
      anil_async_save_original_update
      if AnilAsyncSave.failed_message
        msg = AnilAsyncSave.failed_message
        AnilAsyncSave.failed_message = nil
        pbMessage(msg)
      end
    end
  end
end
