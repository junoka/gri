module GRI
  class PollingUnit
    UNITS = {}

    attr_reader :name, :cat, :oids
    attr_accessor :dhash, :ophash, :options
    alias :defs :dhash

    def self.all_units
      if UNITS.empty?
        for name, dhash in DEFS
          next unless String === name
          pucat = dhash[:cat] || dhash[:pucat] ||
            (dhash[:tdb] and dhash[:tdb].first.intern) || name.intern
          klass = self
          if (puclass = dhash[:puclass])
            if GRI.const_defined?("#{puclass}PollingUnit") or 
                Object.const_defined?("#{puclass}PollingUnit")
              klass = eval("#{puclass}PollingUnit")
            end
          end
          pu = klass.new name, pucat
          pu.dhash = dhash
          pu.set_oids dhash[:oid]
          if dhash[:tdb]
            dhash[:tdb].each {|item|
              if item =~ /\s+\*\s+/
                pre = Regexp.last_match.pre_match
                post = Regexp.last_match.post_match
                (pu.ophash ||= {})[pre] = proc {|val| val * post.to_f}
              end
            }
          end

          self::UNITS[name] = pu
        end
      end
      self::UNITS
    end

    def initialize name, cat
      @name = name
      @cat = cat
      @options = {}
      @ophash = nil
      @d_p = false
    end

    def set_oids names
      @oids = (names || []).map {|name|
        (oid = SNMP::OIDS[name]) ? BER.enc_v_oid(oid) :
          (Log.debug "No such OID: #{name}"; nil)
      }.compact
    end

    def feed wh, enoid, tag, val
      if (feed_proc = dhash[:feed])
        feed_proc.call wh, enoid, tag, val
      else
        if enoid.getbyte(-2) < 128
          ind = enoid.getbyte(-1)
          if ind == 0
            oid_ind = enoid
          else
            oid_ind = enoid[0..-2]
          end
        else
          if enoid.getbyte(-3) < 128
            ind = ((enoid.getbyte(-2) & 0x7f) << 7) + enoid.getbyte(-1)
            oid_ind = enoid[0..-3]
          else
            tmpary = BER.dec_oid enoid
            oid_ind = BER.enc_v_oid(tmpary[0..-2].join('.'))
            ind = tmpary[-1]
          end
        end
        if (sym_oid = SNMP::ROIDS[oid_ind])
          (conv_val_proc = dhash[:conv_val]) and
            (val = conv_val_proc.call(sym_oid, val))
          if ophash and (pr = ophash[sym_oid])
            val = pr.call(val)
          end
          (wh[ind] ||= {})[sym_oid] = val
        end
      end
    end

    def fix_workhash workhash
      if (c = dhash[:fix_workhash])
        if c.arity == 1
          c.call workhash
        elsif c.arity == 2
          c.call workhash, @options
        end
      end
    end

    def inspect
      "#<PU:#{@name}>"
    end
  end

  class HRSWRunPerfPollingUnit < PollingUnit
    def fix_workhash workhash
      re = (pat = options['hrSWRunPerf']) ? Regexp.new(pat) : nil
      wh2 = {}
      if (wh = workhash[:hrSWRunPerf])
        del_keys = []
        for k, v in wh
          sw = "#{v['hrSWRunPath']} #{v['hrSWRunParameters']}"
          if re =~ sw
            matched = $&
            idx = matched.gsub(/[\s\/]/, '_').gsub(/[^\w]/, '') #/
            h = (wh2[idx] ||= {})
            h['hrSWRunPerfMatched'] = matched
            h['hrSWRunPerfMem'] ||= 0
            h['hrSWRunPerfMem'] += v['hrSWRunPerfMem'].to_i * 1024
            h['hrSWRunPerfCPU'] ||= 0
            h['hrSWRunPerfCPU'] += v['hrSWRunPerfCPU'].to_i
          end
        end
        workhash[:hrSWRunPerf] = wh2
      end
      super
    end
  end
end
